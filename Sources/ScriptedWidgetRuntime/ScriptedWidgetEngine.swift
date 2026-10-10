#if canImport(JavaScriptCore)
    import Foundation
    import JavaScriptCore
    import os

    /// What one call into a script produced, plus settings it asked to persist.
    public struct ScriptedEvaluation<Value: Sendable>: Sendable {
        public var value: Value
        /// Settings to write through `widgetUpdateSettings`, already validated. Empty when the
        /// script didn't change any.
        public var settingWrites: [String: String]

        public init(value: Value, settingWrites: [String: String]) {
            self.value = value
            self.settingWrites = settingWrites
        }
    }

    /// Runs one scripted widget's JavaScript in its own `JSContext`. Everything JavaScriptCore
    /// stays inside this actor: `JSContext` and `JSValue` aren't `Sendable`, and `render` hands
    /// out a `ScriptedTile` value decoded from `JSON.stringify` instead. Host functions the script
    /// can call are blocks that capture only `Sendable` things and run inside an evaluation, which
    /// is on this actor's executor.
    ///
    /// Each synchronous call into the script is bounded by JavaScriptCore's own watchdog.
    /// `update()` is asynchronous (it may `await opendock.fetch`) and is also bounded by
    /// `ScriptedWidgetLimits.updateTimeout` of wall-clock time.
    public actor ScriptedWidgetEngine {
        public let package: ScriptedWidgetPackage
        private let limits: ScriptedWidgetLimits
        private let log: @Sendable (String) -> Void
        private let transport: any ScriptedHTTPTransport
        private var context: JSContext?
        private var watchdog: ScriptWatchdog?
        private var mirror: SettingsMirror?
        private var storage: ScriptedWidgetStorage?
        private var activeUpdate: ResumeGate?
        private let inFlight = CounterBox(0)
        private let generationBox = CounterBox(0)

        /// Whether the loaded script defines `update`. False before `load()` succeeds.
        public private(set) var definesUpdate = false

        /// - Parameters:
        ///   - package: The widget to run. `load()` evaluates its script.
        ///   - limits: Time and size budgets.
        ///   - transport: Performs `opendock.fetch`. Tests pass a fake one; the default uses
        ///     `URLSession` and does not follow redirects itself.
        ///   - log: Where `opendock.log(...)` lines go, already prefixed with the widget's id.
        public init(
            package: ScriptedWidgetPackage, limits: ScriptedWidgetLimits = .default,
            transport: any ScriptedHTTPTransport = ScriptedURLSessionTransport(),
            log: @escaping @Sendable (String) -> Void = { _ in }
        ) {
            self.package = package
            self.limits = limits
            self.transport = transport
            self.log = log
        }

        public var isLoaded: Bool { context != nil }

        /// Whether a script that runs past its budget is actually stopped on this system. False
        /// only if JavaScriptCore's time limit entry point can't be found (see `ScriptWatchdog`).
        public nonisolated static var enforcesTimeLimits: Bool { ScriptWatchdog.isEnforced }

        /// Creates the context, installs `opendock`, and evaluates `main.js`. Calling it again
        /// starts over with a fresh context.
        public func load() throws(ScriptedWidgetError) {
            context = nil
            watchdog = nil
            definesUpdate = false
            activeUpdate = nil
            _ = generationBox.increment()
            mirror = SettingsMirror(manifest: package.manifest)
            storage = try ScriptedWidgetStorage(
                fileURL: ScriptedWidgetStorage.fileURL(beside: package.directory, id: package.id), limits: limits)
            guard let context = JSContext() else { throw .javaScriptUnavailable }
            context.name = "OpenDock widget \(package.id)"
            let watchdog = ScriptWatchdog(context: context)
            watchdog.arm(seconds: limits.loadTimeout)
            installAPI(in: context)
            try Self.check(context, watchdog: watchdog, phase: .load, limit: limits.loadTimeout)

            context.evaluateScript(package.script, withSourceURL: package.scriptURL)
            try Self.check(context, watchdog: watchdog, phase: .load, limit: limits.loadTimeout)

            guard context.evaluateScript("typeof render === 'function'")?.toBool() == true else {
                throw .missingRenderFunction
            }
            definesUpdate = context.evaluateScript("typeof update === 'function'")?.toBool() == true
            self.context = context
            self.watchdog = watchdog
        }

        /// Calls `update(context)` and returns the JSON it resolved to (`"null"` when it returned
        /// nothing). The host passes that string back as `context.data` on the next `render`.
        /// A script with no `update` returns `dataJSON` unchanged.
        public func update(
            settings: [String: String], now: Date = .now, compact: Bool = false, locale: Locale = .current,
            dataJSON: String = "null"
        ) async throws(ScriptedWidgetError) -> ScriptedEvaluation<String> {
            _ = generationBox.increment()
            defer { _ = generationBox.increment() }
            let timeout = limits.updateTimeout
            do {
                return try await withThrowingTaskGroup(of: ScriptedEvaluation<String>.self) { group in
                    group.addTask {
                        try await self.performUpdate(
                            settings: settings, now: now, compact: compact, locale: locale, dataJSON: dataJSON)
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(timeout))
                        throw ScriptedWidgetError.timedOut(.update, limit: timeout)
                    }
                    guard let result = try await group.next() else {
                        throw ScriptedWidgetError.timedOut(.update, limit: timeout)
                    }
                    group.cancelAll()
                    return result
                }
            } catch let error as ScriptedWidgetError {
                throw error
            } catch is CancellationError {
                throw .cancelled
            } catch {
                throw .fetchFailed(String(describing: error))
            }
        }

        /// Calls `render(context)` and decodes what it returns. `dataJSON` is the last `update()`
        /// result, or `"null"` when there hasn't been one.
        public func render(
            settings: [String: String], now: Date = .now, compact: Bool = false, locale: Locale = .current,
            dataJSON: String = "null"
        ) throws(ScriptedWidgetError) -> ScriptedEvaluation<ScriptedTile> {
            guard let context, let watchdog else { throw .notLoaded }
            mirror?.reset(to: settings)
            let scriptSettings = package.manifest.scriptSettings(from: settings).mapValues(\.jsonObject)

            watchdog.arm(seconds: limits.renderTimeout)
            let result = context.objectForKeyedSubscript("__opendockCall")?
                .call(
                    withArguments: Self.arguments(
                        name: "render", settings: scriptSettings, now: now, compact: compact, locale: locale,
                        dataJSON: dataJSON))
            do {
                try Self.check(context, watchdog: watchdog, phase: .render, limit: limits.renderTimeout)
            } catch {
                mirror?.discardWrites()
                throw error
            }
            guard let result, !result.isUndefined, !result.isNull else {
                mirror?.discardWrites()
                throw .invalidTile("it returned nothing")
            }

            let json = context.objectForKeyedSubscript("JSON")?.invokeMethod("stringify", withArguments: [result])
            do {
                try Self.check(context, watchdog: watchdog, phase: .render, limit: limits.renderTimeout)
            } catch {
                mirror?.discardWrites()
                throw error
            }
            guard let json, !json.isUndefined, let string = json.toString() else {
                mirror?.discardWrites()
                throw .invalidTile("it isn't a plain object")
            }
            let tile = try ScriptedTile.decode(Data(string.utf8), limits: limits)
            return ScriptedEvaluation(value: tile, settingWrites: mirror?.takeWrites() ?? [:])
        }

        // MARK: Update

        private func performUpdate(
            settings: [String: String], now: Date, compact: Bool, locale: Locale, dataJSON: String
        ) async throws(ScriptedWidgetError) -> ScriptedEvaluation<String> {
            guard let context, let watchdog else { throw .notLoaded }
            guard definesUpdate else {
                return ScriptedEvaluation(value: dataJSON, settingWrites: [:])
            }
            mirror?.reset(to: settings)
            let scriptSettings = package.manifest.scriptSettings(from: settings).mapValues(\.jsonObject)
            watchdog.arm(seconds: limits.updateCPUTimeout)
            let result = context.objectForKeyedSubscript("__opendockCall")?
                .call(
                    withArguments: Self.arguments(
                        name: "update", settings: scriptSettings, now: now, compact: compact, locale: locale,
                        dataJSON: dataJSON))
            do {
                try Self.check(context, watchdog: watchdog, phase: .update, limit: limits.updateCPUTimeout)
            } catch {
                mirror?.discardWrites()
                throw error
            }
            guard let result, !result.isUndefined, !result.isNull else {
                return ScriptedEvaluation(value: "null", settingWrites: mirror?.takeWrites() ?? [:])
            }
            do {
                let json = try await settle(result)
                return ScriptedEvaluation(value: json, settingWrites: mirror?.takeWrites() ?? [:])
            } catch {
                mirror?.discardWrites()
                throw error
            }
        }

        /// Waits until `value` (a promise, or a plain value) settles, with cancellation failing
        /// the wait so a timed-out update can't resume twice.
        private func settle(_ value: JSValue) async throws(ScriptedWidgetError) -> String {
            let gate = ResumeGate()
            activeUpdate = gate
            defer { activeUpdate = nil }
            do {
                let json: String = try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                        gate.arm(continuation)
                        let ok: @convention(block) (String) -> Void = { json in gate.succeed(json) }
                        let fail: @convention(block) (String) -> Void = { payload in
                            gate.fail(Self.error(fromSettlePayload: payload))
                        }
                        guard let context, let watchdog else {
                            gate.fail(.notLoaded)
                            return
                        }
                        watchdog.arm(seconds: limits.updateCPUTimeout)
                        context.objectForKeyedSubscript("__opendockSettle")?.call(withArguments: [value, ok, fail])
                        if watchdog.didFire {
                            context.exception = nil
                            gate.fail(.timedOut(.update, limit: limits.updateCPUTimeout))
                        } else if let exception = context.exception {
                            context.exception = nil
                            gate.fail(Self.classify(exception, phase: .update, limit: limits.updateCPUTimeout))
                        }
                    }
                } onCancel: {
                    gate.fail(.cancelled)
                }
                return json
            } catch let error as ScriptedWidgetError {
                throw error
            } catch {
                throw .cancelled
            }
        }

        // MARK: Host API

        private func installAPI(in context: JSContext) {
            guard let storage, let mirror else { return }
            let network = !package.manifest.permissions.networkHosts.isEmpty
            context.evaluateScript(Self.helpers)

            let getStorage: @convention(block) (String) -> JSValue = { key in
                guard let current = JSContext.current() else { return JSValue(nullIn: context) }
                guard let encoded = storage.jsonString(for: key) else { return JSValue(nullIn: current) }
                return JSValue(object: encoded, in: current) ?? JSValue(nullIn: current)
            }
            let setStorage: @convention(block) (String, JSValue) -> Void = { key, encoded in
                guard let current = JSContext.current() else { return }
                do {
                    if encoded.isNull || encoded.isUndefined {
                        try storage.set(key, value: nil)
                        return
                    }
                    guard let text = encoded.toString(), let json = ScriptedJSON.parse(text) else {
                        throw ScriptedWidgetError.invalidSetting(
                            key: key, detail: "storage.set() needs a value JSON can hold.")
                    }
                    try storage.set(key, value: json)
                } catch let error as ScriptedWidgetError {
                    Self.raise(error, in: current)
                } catch {
                    Self.raise(.storageUnreadable, in: current)
                }
            }
            let getSetting: @convention(block) (String) -> Any = { key in
                mirror.jsonObject(for: key) ?? NSNull()
            }
            let setSetting: @convention(block) (String, JSValue) -> Void = { key, value in
                guard let current = JSContext.current() else { return }
                guard let input = Self.settingInput(from: value) else {
                    Self.raise(
                        .invalidSetting(key: key, detail: "the value's type doesn't match the setting."), in: current)
                    return
                }
                do {
                    try mirror.set(input, for: key)
                } catch let error as ScriptedWidgetError {
                    Self.raise(error, in: current)
                } catch {
                    Self.raise(.invalidSetting(key: key, detail: "the value was refused."), in: current)
                }
            }
            context.setObject(getStorage, forKeyedSubscript: "__opendockStorageGet" as NSString)
            context.setObject(setStorage, forKeyedSubscript: "__opendockStorageSet" as NSString)
            context.setObject(getSetting, forKeyedSubscript: "__opendockSettingsGet" as NSString)
            context.setObject(setSetting, forKeyedSubscript: "__opendockSettingsSet" as NSString)

            guard let api = JSValue(newObjectIn: context) else { return }
            api.setObject(ScriptedWidgetManifest.currentAPIVersion, forKeyedSubscript: "apiVersion" as NSString)
            let log = self.log
            let id = package.id
            let logLine: @convention(block) () -> Void = {
                let parts = (JSContext.currentArguments() as? [JSValue] ?? []).map { $0.toString() ?? "" }
                log("[\(id)] " + parts.joined(separator: " "))
            }
            api.setObject(logLine, forKeyedSubscript: "log" as NSString)
            context.setObject(api, forKeyedSubscript: "opendock" as NSString)

            if network { installFetch(in: context) }
            context.evaluateScript(Self.surface(fetch: network))
        }

        private func installFetch(in context: JSContext) {
            let engine = self
            let inFlight = self.inFlight
            let generationBox = self.generationBox
            let maxInFlight = limits.maxInFlightFetches
            let fetch: @convention(block) (String, String, String, JSValue) -> JSValue = {
                url, method, headersJSON, body in
                guard let current = JSContext.current() else { return JSValue(undefinedIn: context) }
                let bodyText: String? = body.isNull || body.isUndefined ? nil : body.toString()
                // The executor label stays explicit. A trailing closure here is parsed as the
                // body of the surrounding `guard`.
                let promise = JSValue(
                    newPromiseIn: current,
                    fromExecutor: { resolve, reject in
                        guard let resolve, let reject else { return }
                        guard inFlight.begin(max: maxInFlight) else {
                            let error = JSValue(
                                newErrorFromMessage: "Too many fetches at once; the most is \(maxInFlight).",
                                in: current)
                            error?.setObject("fetchFailed", forKeyedSubscript: "code" as NSString)
                            reject.call(withArguments: [error as Any])
                            return
                        }
                        let box = PromiseBox(resolve: resolve, reject: reject)
                        let generation = generationBox.get()
                        Task {
                            await engine.completeFetch(
                                urlString: url, method: method, headersJSON: headersJSON, body: bodyText, box: box,
                                generation: generation)
                        }
                    })
                guard let promise else { return JSValue(undefinedIn: current) }
                return promise
            }
            context.setObject(fetch, forKeyedSubscript: "__opendockFetch" as NSString)
        }

        private func completeFetch(
            urlString: String, method: String, headersJSON: String, body: String?, box: PromiseBox, generation: Int
        ) async {
            defer { inFlight.end() }
            guard generation == generationBox.get(), let context, let watchdog else { return }
            do {
                guard let url = URL(string: urlString) else {
                    box.fail(.fetchFailed("The fetch URL isn't valid."))
                    return
                }
                let client = ScriptedFetchClient(
                    transport: transport, limits: limits, patterns: package.manifest.permissions.networkHosts)
                let response = try await client.fetch(
                    url: url, method: method, headers: Self.headers(from: headersJSON),
                    body: body.map { Data($0.utf8) })
                guard generation == generationBox.get() else { return }
                let payload = try response.payload()
                watchdog.arm(seconds: limits.updateCPUTimeout)
                box.succeed(payload)
                if watchdog.didFire {
                    context.exception = nil
                    activeUpdate?.fail(.timedOut(.update, limit: limits.updateCPUTimeout))
                }
            } catch let error as ScriptedWidgetError {
                guard generation == generationBox.get() else { return }
                box.fail(error)
            } catch is CancellationError {
                return
            } catch {
                guard generation == generationBox.get() else { return }
                box.fail(.fetchFailed(String(describing: error)))
            }
        }

        private static func arguments(
            name: String, settings: [String: Any], now: Date, compact: Bool, locale: Locale, dataJSON: String
        ) -> [Any] {
            [
                name, settings, now.timeIntervalSince1970 * 1000, compact ? "compact" : "regular", locale.identifier,
                dataJSON,
            ]
        }

        private static func headers(from json: String) -> [String: String] {
            guard let data = json.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return [:] }
            var headers: [String: String] = [:]
            for (key, value) in object {
                headers[key] = String(describing: value)
            }
            return headers
        }

        private static func settingInput(from value: JSValue) -> ScriptedSettingsWrite.Input? {
            if value.isUndefined || value.isNull { return nil }
            if value.isBoolean { return .bool(value.toBool()) }
            if value.isString, let string = value.toString() { return .string(string) }
            if value.isNumber { return .number(value.toDouble()) }
            return nil
        }

        /// Turns a pending exception into an error, and clears it.
        private static func check(
            _ context: JSContext, watchdog: ScriptWatchdog, phase: ScriptedWidgetError.Phase, limit: TimeInterval
        ) throws(ScriptedWidgetError) {
            guard let exception = context.exception else { return }
            context.exception = nil
            if watchdog.didFire { throw .timedOut(phase, limit: limit) }
            throw classify(exception, phase: phase, limit: limit)
        }

        private static func classify(
            _ exception: JSValue, phase: ScriptedWidgetError.Phase, limit: TimeInterval
        ) -> ScriptedWidgetError {
            let message = exception.toString() ?? "Error"
            let line = exception.objectForKeyedSubscript("line").flatMap { $0.isNumber ? Int($0.toInt32()) : nil }
            let code = exception.objectForKeyedSubscript("code")?.toString()
            switch code {
            case "networkDenied":
                let host = exception.objectForKeyedSubscript("host")?.toString() ?? ""
                return .networkDenied(host: host.isEmpty ? message : host)
            case "fetchFailed":
                return .fetchFailed(message)
            case "storageTooLarge":
                let bytes = exception.objectForKeyedSubscript("bytes").map { Int($0.toInt32()) } ?? 0
                let cap = exception.objectForKeyedSubscript("limit").map { Int($0.toInt32()) } ?? 0
                return .storageTooLarge(bytes: bytes, limit: cap)
            case "invalidSetting":
                return .exception(message: message, line: line)
            default:
                return .exception(message: message, line: line)
            }
        }

        /// Parses the JSON `__opendockSettle` sends when a promise rejects.
        private static func error(fromSettlePayload payload: String) -> ScriptedWidgetError {
            guard let data = payload.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return .exception(message: payload, line: nil) }
            let message = object["message"] as? String ?? payload
            let line = (object["line"] as? NSNumber).map { Int(truncating: $0) }
            let code = object["code"] as? String
            let host = object["host"] as? String
            switch code {
            case "networkDenied":
                return .networkDenied(host: host?.isEmpty == false ? host! : message)
            case "fetchFailed":
                return .fetchFailed(message)
            case "storageTooLarge":
                let bytes = (object["bytes"] as? NSNumber).map { Int(truncating: $0) } ?? 0
                let cap = (object["limit"] as? NSNumber).map { Int(truncating: $0) } ?? 0
                return .storageTooLarge(bytes: bytes, limit: cap)
            case "invalidSetting":
                return .exception(message: message, line: line)
            default:
                return .exception(message: message, line: line)
            }
        }

        private static func raise(_ error: ScriptedWidgetError, in context: JSContext) {
            let exception = JSValue(newErrorFromMessage: error.description, in: context)
            switch error {
            case let .networkDenied(host):
                exception?.setObject("networkDenied", forKeyedSubscript: "code" as NSString)
                exception?.setObject(host, forKeyedSubscript: "host" as NSString)
            case .fetchFailed:
                exception?.setObject("fetchFailed", forKeyedSubscript: "code" as NSString)
            case let .storageTooLarge(bytes, limit):
                exception?.setObject("storageTooLarge", forKeyedSubscript: "code" as NSString)
                exception?.setObject(bytes, forKeyedSubscript: "bytes" as NSString)
                exception?.setObject(limit, forKeyedSubscript: "limit" as NSString)
            case let .invalidSetting(key, _):
                exception?.setObject("invalidSetting", forKeyedSubscript: "code" as NSString)
                exception?.setObject(key, forKeyedSubscript: "key" as NSString)
            default:
                break
            }
            context.exception = exception
        }

        /// Helpers installed before the script runs. `__opendockCall` and `__opendockSettle` are
        /// how the host invokes `render`/`update` and waits out a promise.
        private static let helpers = """
            Object.defineProperty(globalThis, "__opendockCall", {
              value: function(name, settings, now, size, locale, dataJSON) {
                return globalThis[name]({
                  settings: settings, now: now, size: size, locale: locale, data: JSON.parse(dataJSON)
                });
              },
              writable: false, configurable: false, enumerable: false
            });
            Object.defineProperty(globalThis, "__opendockSettle", {
              value: function(value, onSuccess, onFailure) {
                Promise.resolve(value).then(function(resolved) {
                  try {
                    onSuccess(JSON.stringify(resolved === undefined ? null : resolved));
                  } catch (error) {
                    onFailure(JSON.stringify({
                      message: String(error && error.message || error),
                      line: error && error.line || null
                    }));
                  }
                }, function(error) {
                  onFailure(JSON.stringify({
                    message: String(error && (error.message || error) || "Error"),
                    line: error && error.line || null,
                    code: error && error.code || null,
                    host: error && error.host || null,
                    bytes: error && error.bytes || null,
                    limit: error && error.limit || null,
                    key: error && error.key || null
                  }));
                });
              },
              writable: false, configurable: false, enumerable: false
            });
            """

        private static func surface(fetch: Bool) -> String {
            var script = """
                opendock.storage = Object.freeze({
                  get: function(key) {
                    var raw = __opendockStorageGet(String(key));
                    return raw == null ? null : JSON.parse(raw);
                  },
                  set: function(key, value) {
                    if (arguments.length < 2 || value === undefined) {
                      __opendockStorageSet(String(key), null);
                      return;
                    }
                    var encoded = JSON.stringify(value);
                    if (encoded === undefined) throw new Error("storage.set() needs a value JSON can hold.");
                    __opendockStorageSet(String(key), encoded);
                  }
                });
                opendock.settings = Object.freeze({
                  get: function(key) { return __opendockSettingsGet(String(key)); },
                  set: function(key, value) { __opendockSettingsSet(String(key), value); }
                });
                """
            if fetch {
                script += """
                    opendock.fetch = function(url, options) {
                      options = options || {};
                      var method = String(options.method || "GET").toUpperCase();
                      var headers = {};
                      var incoming = options.headers || {};
                      for (var name in incoming) {
                        if (Object.prototype.hasOwnProperty.call(incoming, name)) {
                          headers[name] = String(incoming[name]);
                        }
                      }
                      var body = null;
                      if (options.body !== undefined && options.body !== null) {
                        if (typeof options.body === "string") {
                          body = options.body;
                          if (headers["Content-Type"] === undefined && headers["content-type"] === undefined) {
                            headers["Content-Type"] = "text/plain;charset=UTF-8";
                          }
                        } else {
                          body = JSON.stringify(options.body);
                          if (headers["Content-Type"] === undefined && headers["content-type"] === undefined) {
                            headers["Content-Type"] = "application/json";
                          }
                        }
                      }
                      return __opendockFetch(String(url), method, JSON.stringify(headers), body).then(function(raw) {
                        var parsed = JSON.parse(raw);
                        return {
                          status: parsed.status,
                          ok: parsed.status >= 200 && parsed.status < 300,
                          headers: parsed.headers,
                          text: function() { return Promise.resolve(parsed.body); },
                          json: function() { return Promise.resolve(JSON.parse(parsed.body)); }
                        };
                      });
                    };
                    """
            }
            script += "Object.freeze(opendock);"
            return script
        }
    }

    /// One fetch's resolve and reject, touched only on the engine's actor.
    private final class PromiseBox: @unchecked Sendable {
        private let resolveFunction: JSValue
        private let rejectFunction: JSValue

        init(resolve: JSValue, reject: JSValue) {
            self.resolveFunction = resolve
            self.rejectFunction = reject
        }

        func succeed(_ json: String) {
            resolveFunction.call(withArguments: [json])
        }

        func fail(_ error: ScriptedWidgetError) {
            guard let context = resolveFunction.context else { return }
            let exception = JSValue(newErrorFromMessage: error.description, in: context)
            switch error {
            case let .networkDenied(host):
                exception?.setObject("networkDenied", forKeyedSubscript: "code" as NSString)
                exception?.setObject(host, forKeyedSubscript: "host" as NSString)
            case .fetchFailed:
                exception?.setObject("fetchFailed", forKeyedSubscript: "code" as NSString)
            case let .storageTooLarge(bytes, limit):
                exception?.setObject("storageTooLarge", forKeyedSubscript: "code" as NSString)
                exception?.setObject(bytes, forKeyedSubscript: "bytes" as NSString)
                exception?.setObject(limit, forKeyedSubscript: "limit" as NSString)
            case let .invalidSetting(key, _):
                exception?.setObject("invalidSetting", forKeyedSubscript: "code" as NSString)
                exception?.setObject(key, forKeyedSubscript: "key" as NSString)
            default:
                break
            }
            if let exception { rejectFunction.call(withArguments: [exception]) }
        }
    }

    /// Resumes a continuation exactly once. The success path can run before `arm`, from inside
    /// the call that installs it.
    private final class ResumeGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<String, Error>?
        private var pending: Result<String, ScriptedWidgetError>?
        private var resumed = false

        func arm(_ continuation: CheckedContinuation<String, Error>) {
            let pending: Result<String, ScriptedWidgetError>? = lock.withLock {
                if resumed { return self.pending }
                self.continuation = continuation
                return nil
            }
            if let pending { continuation.resume(with: pending.mapError { $0 }) }
        }

        func succeed(_ value: String) { finish(.success(value)) }
        func fail(_ error: ScriptedWidgetError) { finish(.failure(error)) }

        private func finish(_ result: Result<String, ScriptedWidgetError>) {
            let continuation: CheckedContinuation<String, Error>? = lock.withLock {
                if resumed { return nil }
                resumed = true
                pending = result
                let continuation = self.continuation
                self.continuation = nil
                return continuation
            }
            continuation?.resume(with: result.mapError { $0 })
        }
    }

    /// The settings a script can read and write during one call, and which of them changed.
    private final class SettingsMirror: @unchecked Sendable {
        let manifest: ScriptedWidgetManifest
        private let lock = NSLock()
        private var settings: [String: String] = [:]
        private var writes: [String: String] = [:]

        init(manifest: ScriptedWidgetManifest) {
            self.manifest = manifest
        }

        func reset(to settings: [String: String]) {
            lock.withLock {
                self.settings = settings
                writes = [:]
            }
        }

        func jsonObject(for key: String) -> Any? {
            let settings = lock.withLock { self.settings }
            return manifest.scriptSettings(from: settings)[key]?.jsonObject
        }

        func set(_ input: ScriptedSettingsWrite.Input, for key: String) throws(ScriptedWidgetError) {
            let stored = try ScriptedSettingsWrite.storedString(input, for: key, in: manifest)
            lock.withLock {
                guard settings[key] != stored else { return }
                settings[key] = stored
                writes[key] = stored
            }
        }

        func takeWrites() -> [String: String] {
            lock.withLock {
                let writes = self.writes
                self.writes = [:]
                return writes
            }
        }

        func discardWrites() {
            lock.withLock { writes = [:] }
        }
    }

    /// A small integer protected by a lock: the fetch generation, and how many fetches are in flight.
    private final class CounterBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int

        init(_ value: Int) { self.value = value }

        func get() -> Int { lock.withLock { value } }

        @discardableResult
        func increment() -> Int {
            lock.withLock {
                value += 1
                return value
            }
        }

        /// False when `value` is already `max`.
        func begin(max: Int) -> Bool {
            lock.withLock {
                if value >= max { return false }
                value += 1
                return true
            }
        }

        func end() { lock.withLock { value = max(0, value - 1) } }
    }

    /// JavaScriptCore's execution time limit. The entry point, `JSContextGroupSetExecutionTimeLimit`,
    /// is declared in a header the SDK doesn't ship (`JSContextRefPrivate.h`), so it's resolved by
    /// name at run time; without it, calls aren't bounded and `isEnforced` says so. The budget is
    /// per entry into the VM: each `arm` sets it for the calls that follow. When it runs out,
    /// JavaScriptCore stops the script with an uncatchable exception and `didFire` is set.
    final class ScriptWatchdog {
        private typealias SetLimit =
            @convention(c) (
                JSContextGroupRef?, Double, (@convention(c) (JSContextRef?, UnsafeMutableRawPointer?) -> Bool)?,
                UnsafeMutableRawPointer?
            ) -> Void

        private typealias ClearLimit = @convention(c) (JSContextGroupRef?) -> Void

        private static let setLimit: SetLimit? = {
            guard let handle = dlopen(nil, RTLD_LAZY),
                let symbol = dlsym(handle, "JSContextGroupSetExecutionTimeLimit")
            else { return nil }
            return unsafeBitCast(symbol, to: SetLimit.self)
        }()

        private static let clearLimit: ClearLimit? = {
            guard let handle = dlopen(nil, RTLD_LAZY),
                let symbol = dlsym(handle, "JSContextGroupClearExecutionTimeLimit")
            else { return nil }
            return unsafeBitCast(symbol, to: ClearLimit.self)
        }()

        /// Whether the time limit can be enforced on this system.
        static var isEnforced: Bool { setLimit != nil }

        /// Retained, so the group outlives the callback pointer registered on it.
        private let group: JSContextGroupRef?
        private let fired = OSAllocatedUnfairLock(initialState: false)

        init(context: JSContext) {
            group = JSContextGroupRetain(JSContextGetGroup(context.jsGlobalContextRef))
        }

        deinit {
            if let group {
                Self.clearLimit?(group)
                JSContextGroupRelease(group)
            }
        }

        var didFire: Bool { fired.withLock { $0 } }

        /// Gives the next calls into the context `seconds` of CPU time each.
        func arm(seconds: TimeInterval) {
            fired.withLock { $0 = false }
            guard let setLimit = Self.setLimit else { return }
            let callback: @convention(c) (JSContextRef?, UnsafeMutableRawPointer?) -> Bool = { _, info in
                if let info {
                    Unmanaged<ScriptWatchdog>.fromOpaque(info).takeUnretainedValue().fired.withLock { $0 = true }
                }
                return true
            }
            setLimit(group, seconds, callback, Unmanaged.passUnretained(self).toOpaque())
        }
    }
#endif
