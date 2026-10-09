#if canImport(JavaScriptCore)
    import Foundation
    import JavaScriptCore
    import os

    /// Runs one scripted widget's JavaScript in its own `JSContext`. Everything JavaScriptCore
    /// stays inside this actor: `JSContext` and `JSValue` aren't `Sendable`, and `render` hands
    /// out a `ScriptedTile` value decoded from `JSON.stringify` instead. Host functions the script
    /// can call are blocks that capture only `Sendable` things and run inside an evaluation, which
    /// is on this actor's executor.
    ///
    /// Each call into the script is bounded by JavaScriptCore's own watchdog
    /// (`ScriptedWidgetLimits.loadTimeout` and `renderTimeout`, in CPU seconds); a script that runs
    /// past it is stopped and the call throws `.timedOut`.
    public actor ScriptedWidgetEngine {
        public let package: ScriptedWidgetPackage
        private let limits: ScriptedWidgetLimits
        private let log: @Sendable (String) -> Void
        private var context: JSContext?
        private var watchdog: ScriptWatchdog?

        /// - Parameters:
        ///   - package: The widget to run. `load()` evaluates its script.
        ///   - limits: Time and size budgets.
        ///   - log: Where `opendock.log(...)` lines go, already prefixed with the widget's id.
        public init(
            package: ScriptedWidgetPackage, limits: ScriptedWidgetLimits = .default,
            log: @escaping @Sendable (String) -> Void = { _ in }
        ) {
            self.package = package
            self.limits = limits
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
            guard let context = JSContext() else { throw .javaScriptUnavailable }
            context.name = "OpenDock widget \(package.id)"
            installAPI(in: context)

            let watchdog = ScriptWatchdog(context: context)
            watchdog.arm(seconds: limits.loadTimeout)
            context.evaluateScript(package.script, withSourceURL: package.scriptURL)
            try Self.check(context, watchdog: watchdog, phase: .load, limit: limits.loadTimeout)

            guard context.evaluateScript("typeof render === 'function'")?.toBool() == true else {
                throw .missingRenderFunction
            }
            self.context = context
            self.watchdog = watchdog
        }

        /// Calls `render(context)` and decodes what it returns.
        ///
        /// - Parameters:
        ///   - settings: The tile's stored settings; the script sees them typed and validated
        ///     through the manifest's schema.
        ///   - now: What `context.now` says, in case a test wants to pin it.
        ///   - compact: Whether the tile is one icon wide (on a side edge of the screen).
        ///   - locale: What `context.locale` says.
        public func render(
            settings: [String: String], now: Date = .now, compact: Bool = false, locale: Locale = .current
        ) throws(ScriptedWidgetError) -> ScriptedTile {
            guard let context, let watchdog else { throw .notLoaded }
            let scriptSettings = package.manifest.scriptSettings(from: settings).mapValues(\.jsonObject)
            let argument: [String: Any] = [
                "settings": scriptSettings,
                "now": now.timeIntervalSince1970 * 1000,
                "size": compact ? "compact" : "regular",
                "locale": locale.identifier,
            ]

            watchdog.arm(seconds: limits.renderTimeout)
            let result = context.objectForKeyedSubscript("render")?.call(withArguments: [argument])
            try Self.check(context, watchdog: watchdog, phase: .render, limit: limits.renderTimeout)
            guard let result, !result.isUndefined, !result.isNull else {
                throw .invalidTile("it returned nothing")
            }

            let json = context.objectForKeyedSubscript("JSON")?.invokeMethod("stringify", withArguments: [result])
            try Self.check(context, watchdog: watchdog, phase: .render, limit: limits.renderTimeout)
            guard let json, !json.isUndefined, let string = json.toString() else {
                throw .invalidTile("it isn't a plain object")
            }
            return try ScriptedTile.decode(Data(string.utf8), limits: limits)
        }

        // MARK: Host API

        private func installAPI(in context: JSContext) {
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
            context.evaluateScript("Object.freeze(opendock);")
        }

        /// Turns a pending exception into an error, and clears it.
        private static func check(
            _ context: JSContext, watchdog: ScriptWatchdog, phase: ScriptedWidgetError.Phase, limit: TimeInterval
        ) throws(ScriptedWidgetError) {
            guard let exception = context.exception else { return }
            context.exception = nil
            if watchdog.didFire {
                throw .timedOut(phase, limit: limit)
            }
            let message = exception.toString() ?? "Error"
            let line = exception.objectForKeyedSubscript("line").flatMap { $0.isNumber ? Int($0.toInt32()) : nil }
            throw .exception(message: message, line: line)
        }
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
