#if canImport(JavaScriptCore)
    import Foundation
    import ScriptedWidgetRuntime
    import Testing

    /// The JavaScriptCore engine, against the `hello` sample and small scripts written here.
    /// These only build where JavaScriptCore exists (macOS), which CI is.
    @Suite("Scripted widget engine")
    struct EngineTests {
        private static let noon = Date(timeIntervalSince1970: 1_760_000_000)

        private func engine(
            script: String, settings: String = "[]", permissions: String = "{}",
            limits: ScriptedWidgetLimits = .default, transport: (any ScriptedHTTPTransport)? = nil
        ) throws -> ScriptedWidgetEngine {
            let directory = try SampleWidget.makePackage(
                manifest: SampleWidget.manifest(settings: settings, permissions: permissions), script: script)
            let package = try ScriptedWidgetPackage.load(from: directory)
            if let transport {
                return ScriptedWidgetEngine(package: package, limits: limits, transport: transport)
            }
            return ScriptedWidgetEngine(package: package, limits: limits)
        }

        /// The `ScriptedWidgetError` that `body` throws, or nil when it doesn't throw one.
        private func failure(of body: () async throws -> Void) async -> ScriptedWidgetError? {
            do {
                try await body()
                return nil
            } catch let error as ScriptedWidgetError {
                return error
            } catch {
                Issue.record("expected a ScriptedWidgetError, got \(error)")
                return nil
            }
        }

        @Test func rendersTheHelloSample() async throws {
            let package = try ScriptedWidgetPackage.load(from: SampleWidget.directory)
            let engine = ScriptedWidgetEngine(package: package)
            try await engine.load()
            #expect(await engine.isLoaded)

            let tile = try await engine.render(settings: [:], now: Self.noon).value
            #expect(tile.refresh == 1)
            #expect(tile.minWidth == 3)
            #expect(tile.elements.count == 2)
            guard case let .progress(ring) = tile.elements[0], case let .column(column) = tile.elements[1] else {
                Issue.record("unexpected elements \(tile.elements)")
                return
            }
            let seconds = Calendar(identifier: .gregorian).component(.second, from: Self.noon)
            #expect(ring.fraction == Double(seconds) / 60)
            #expect(ring.label == String(seconds))
            #expect(ring.color == .named(.teal))
            #expect(
                column.children == [
                    .text(ScriptedText("Hello, World")), .text(ScriptedText("Rendered once", style: .secondary)),
                ])
            #expect(tile.accessibilityLabel == "Hello, World. Rendered 1 times.")

            let second = try await engine.render(
                settings: ["name": "Oslo", "showRing": "false", "refreshSeconds": "60"], now: Self.noon
            ).value
            #expect(second.refresh == 60)
            #expect(second.elements.count == 1)
            guard case let .column(again) = second.elements[0] else {
                Issue.record("unexpected elements \(second.elements)")
                return
            }
            #expect(again.children.first == .text(ScriptedText("Hello, Oslo")))
            #expect(again.children.last == .text(ScriptedText("Rendered 2×", style: .secondary)))

            let compact = try await engine.render(settings: [:], now: Self.noon, compact: true).value
            guard case let .column(stacked) = compact.elements[1] else {
                Issue.record("unexpected elements \(compact.elements)")
                return
            }
            #expect(stacked.alignment == .center)
        }

        @Test func passesTypedSettingsAndContext() async throws {
            let engine = try engine(
                script: """
                    function render(context) {
                      const s = context.settings;
                      return { elements: [
                        { type: "text", text: [typeof s.flag, typeof s.count, typeof s.name, typeof context.now, context.size, typeof context.locale].join(" ") },
                        { type: "text", text: String(s.flag) + " " + s.count + " " + s.name + " " + context.now + " " + opendock.apiVersion },
                      ] };
                    }
                    """,
                settings: """
                    [{"key": "flag", "type": "bool", "default": true, "summary": "F."},
                     {"key": "count", "type": "integer", "min": 0, "max": 9, "default": 4, "summary": "C."},
                     {"key": "name", "type": "text", "default": "x", "summary": "N."}]
                    """)
            try await engine.load()
            let tile = try await engine.render(settings: ["count": "42", "flag": "false"], now: Self.noon).value
            #expect(tile.elements[0] == .text(ScriptedText("boolean number string number regular string")))
            #expect(tile.elements[1] == .text(ScriptedText("false 4 x 1760000000000 1")))
        }

        @Test func reportsExceptionsWithTheirLine() async throws {
            let engine = try engine(
                script: """
                    function render() {
                      const nothing = undefined;
                      return nothing.property;
                    }
                    """)
            try await engine.load()
            let failed = await failure { _ = try await engine.render(settings: [:]) }
            guard case let .exception(message, line) = failed else {
                Issue.record("expected an exception, got \(String(describing: failed))")
                return
            }
            #expect(message.hasPrefix("TypeError"))
            #expect(line == 3)

            let syntax = try self.engine(script: "let x = ;")
            let loadError = await failure { try await syntax.load() }
            guard case let .exception(loadMessage, _) = loadError else {
                Issue.record("expected a syntax error, got \(String(describing: loadError))")
                return
            }
            #expect(loadMessage.hasPrefix("SyntaxError"))

            let thrown = try self.engine(script: "function render() { throw new Error('nope'); }")
            try await thrown.load()
            #expect(
                await failure { _ = try await thrown.render(settings: [:]) }
                    == .exception(message: "Error: nope", line: 1))
        }

        @Test func requiresARenderFunction() async throws {
            let constant = try engine(script: "const render = 3;")
            #expect(await failure { try await constant.load() } == .missingRenderFunction)
            let empty = try engine(script: "")
            #expect(await failure { try await empty.load() } == .missingRenderFunction)
            let unloaded = try engine(script: "function render() {}")
            #expect(await failure { _ = try await unloaded.render(settings: [:]) } == .notLoaded)
        }

        @Test func rejectsWhatIsNotATile() async throws {
            /// The error `render()` of `script` fails with.
            func renderError(_ script: String) async throws -> ScriptedWidgetError? {
                let engine = try engine(script: script)
                try await engine.load()
                return await failure { _ = try await engine.render(settings: [:]) }
            }
            #expect(try await renderError("function render() {}") == .invalidTile("it returned nothing"))
            #expect(try await renderError("function render() { return null; }") == .invalidTile("it returned nothing"))
            #expect(
                try await renderError("function render() { return 'hello'; }")
                    == .invalidTile("the tile has the wrong type"))
            #expect(
                try await renderError("function render() { return () => 1; }")
                    == .invalidTile("it isn't a plain object"))
            #expect(
                try await renderError("function render() { return { elements: [{ type: 'text' }] }; }")
                    == .invalidTile("elements[0] is missing \"text\""))

            let cycle = try await renderError(
                "function render() { const o = {}; o.self = o; return { elements: [o] }; }")
            guard case let .exception(message, _) = cycle else {
                Issue.record("expected JSON.stringify to throw, got \(String(describing: cycle))")
                return
            }
            #expect(message.hasPrefix("TypeError"))
        }

        @Test func stopsAScriptThatRunsTooLong() async throws {
            guard ScriptedWidgetEngine.enforcesTimeLimits else {
                Issue.record("JavaScriptCore's execution time limit isn't available; a runaway script would hang")
                return
            }
            var limits = ScriptedWidgetLimits()
            limits.loadTimeout = 0.2
            limits.renderTimeout = 0.2

            let armed = try engine(script: "function render() { while (true) {} }", limits: limits)
            try await armed.load()
            let started = Date()
            #expect(await failure { _ = try await armed.render(settings: [:]) } == .timedOut(.render, limit: 0.2))
            #expect(Date().timeIntervalSince(started) < 5)

            // The context survives a timeout: the next call runs normally.
            let fine = try self.engine(
                script: """
                    let calls = 0;
                    function render() {
                      calls += 1;
                      if (calls === 1) { while (true) {} }
                      return { elements: [{ type: "text", text: "call " + calls }] };
                    }
                    """, limits: limits)
            try await fine.load()
            #expect(await failure { _ = try await fine.render(settings: [:]) } == .timedOut(.render, limit: 0.2))
            #expect(try await fine.render(settings: [:]).value.elements == [.text(ScriptedText("call 2"))])

            let atLoad = try self.engine(script: "while (true) {}", limits: limits)
            #expect(await failure { try await atLoad.load() } == .timedOut(.load, limit: 0.2))
            #expect(await !atLoad.isLoaded)
        }

        @Test func forwardsLogLines() async throws {
            let lines = LogSink()
            let directory = try SampleWidget.makePackage(
                manifest: SampleWidget.manifest(),
                script: """
                    opendock.log("loaded", 1, true, { a: 1 });
                    function render() { opendock.log("render"); return { elements: [] }; }
                    """)
            let engine = ScriptedWidgetEngine(package: try ScriptedWidgetPackage.load(from: directory)) { line in
                lines.append(line)
            }
            try await engine.load()
            _ = try await engine.render(settings: [:])
            #expect(lines.all == ["[com.example.test] loaded 1 true [object Object]", "[com.example.test] render"])
        }

        @Test func keepsTheHostObjectFrozen() async throws {
            let engine = try engine(
                script: """
                    function render() {
                      let changed = "no";
                      try { opendock.log = () => { changed = "yes"; }; opendock.log(); } catch (e) { changed = "threw"; }
                      return { elements: [{ type: "text", text: changed + " " + typeof opendock.fetch + " " + typeof setTimeout + " " + typeof require }] };
                    }
                    """)
            try await engine.load()
            let tile = try await engine.render(settings: [:]).value
            #expect(tile.elements == [.text(ScriptedText("no undefined undefined undefined"))])
        }

        @Test func passesTheUpdateResultToRender() async throws {
            let engine = try engine(
                script: """
                    async function update(context) {
                      return { temperature: 12.5, previous: context.data };
                    }
                    function render(context) {
                      return { elements: [{ type: "text", text: String(context.data.temperature) }] };
                    }
                    """)
            try await engine.load()
            #expect(await engine.definesUpdate)
            let updated = try await engine.update(settings: [:])
            #expect(updated.value.contains("12.5"))
            #expect(updated.settingWrites.isEmpty)
            let tile = try await engine.render(settings: [:], dataJSON: updated.value).value
            #expect(tile.elements == [.text(ScriptedText("12.5"))])
        }

        @Test func leavesDataNullWhenThereIsNoUpdate() async throws {
            let engine = try engine(
                script: """
                    function render(context) {
                      const kind = typeof opendock.storage.get;
                      return { elements: [{ type: "text", text: String(context.data) + " " + kind }] };
                    }
                    """)
            try await engine.load()
            #expect(await !engine.definesUpdate)
            let tile = try await engine.render(settings: [:]).value
            #expect(tile.elements == [.text(ScriptedText("null function"))])
        }

        @Test func fetchToADeniedHostFailsBeforeConnecting() async throws {
            let transport = FakeTransport { _ in
                Issue.record("fetch contacted a host that isn't allowed")
                return ScriptedHTTPResponse(status: 200, headers: [:], body: Data("no".utf8))
            }
            let engine = try engine(
                script: """
                    async function update() {
                      await opendock.fetch("https://evil.example/secret");
                      return { ok: true };
                    }
                    function render() { return { elements: [] }; }
                    """, permissions: #"{"network": ["api.github.com"]}"#, transport: transport)
            try await engine.load()
            let denied = await failure { _ = try await engine.update(settings: [:]) }
            #expect(denied == .networkDenied(host: "evil.example"))
            #expect(transport.calls.isEmpty)
        }

        @Test func fetchReturnsJSONAndPostsABody() async throws {
            let transport = FakeTransport { request in
                let body = request.body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let object = ["method": request.method, "body": body]
                let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
                return ScriptedHTTPResponse(status: 200, headers: ["content-type": "application/json"], body: data)
            }
            let engine = try engine(
                script: """
                    async function update() {
                      const response = await opendock.fetch("https://api.github.com/repos/x", {
                        method: "POST", body: { a: 1 }
                      });
                      return await response.json();
                    }
                    function render(context) {
                      return { elements: [{ type: "text", text: context.data.method + " " + context.data.body }] };
                    }
                    """, permissions: #"{"network": ["api.github.com"]}"#, transport: transport)
            try await engine.load()
            let updated = try await engine.update(settings: [:])
            let tile = try await engine.render(settings: [:], dataJSON: updated.value).value
            #expect(tile.elements == [.text(ScriptedText(#"POST {"a":1}"#))])
            #expect(transport.calls.count == 1)
            #expect(transport.calls[0].method == "POST")
            #expect(transport.calls[0].headers["Content-Type"] == "application/json")
            #expect(transport.calls[0].url.host == "api.github.com")
        }

        @Test func anOffListRedirectIsTheTilesError() async throws {
            let transport = FakeTransport { _ in
                ScriptedHTTPResponse(
                    status: 302, headers: ["location": "https://evil.example/away"], body: Data())
            }
            let engine = try engine(
                script: """
                    async function update() {
                      await opendock.fetch("https://api.github.com/start");
                      return {};
                    }
                    function render() { return { elements: [] }; }
                    """, permissions: #"{"network": ["api.github.com"]}"#, transport: transport)
            try await engine.load()
            #expect(
                await failure { _ = try await engine.update(settings: [:]) } == .networkDenied(host: "evil.example"))
            #expect(transport.calls.count == 1)
        }

        @Test func storageSurvivesANewEngine() async throws {
            let script = """
                function render() {
                  const n = opendock.storage.get("count");
                  const next = (n == null ? 0 : n) + 1;
                  opendock.storage.set("count", next);
                  return { elements: [{ type: "text", text: String(next) }] };
                }
                """
            let directory = try SampleWidget.makePackage(manifest: SampleWidget.manifest(), script: script)
            let package = try ScriptedWidgetPackage.load(from: directory)
            let first = ScriptedWidgetEngine(package: package)
            try await first.load()
            #expect(try await first.render(settings: [:]).value.elements == [.text(ScriptedText("1"))])
            let second = ScriptedWidgetEngine(package: package)
            try await second.load()
            #expect(try await second.render(settings: [:]).value.elements == [.text(ScriptedText("2"))])
        }

        @Test func settingsSetPersistsAValidValueAndRejectsTheRest() async throws {
            let engine = try engine(
                script: """
                    function render(context) {
                      opendock.settings.set("name", "Oslo");
                      return { elements: [{ type: "text", text: opendock.settings.get("name") }] };
                    }
                    """,
                settings: #"[{"key": "name", "type": "text", "default": "World", "summary": "Who."}]"#)
            try await engine.load()
            let wrote = try await engine.render(settings: [:])
            #expect(wrote.settingWrites == ["name": "Oslo"])
            #expect(wrote.value.elements == [.text(ScriptedText("Oslo"))])
            let again = try await engine.render(settings: ["name": "Oslo"])
            #expect(again.settingWrites.isEmpty)

            let refused = try self.engine(
                script: """
                    function render() {
                      opendock.settings.set("count", 99);
                      return { elements: [] };
                    }
                    """,
                settings: #"[{"key": "count", "type": "integer", "min": 0, "max": 9, "default": 1, "summary": "C."}]"#)
            try await refused.load()
            let failed = await failure { _ = try await refused.render(settings: [:]) }
            guard case let .exception(message, _) = failed else {
                Issue.record("expected a settings error, got \(String(describing: failed))")
                return
            }
            #expect(message.contains("count"))
        }

        @Test func updateGivesUpAfterItsBudget() async throws {
            var limits = ScriptedWidgetLimits()
            limits.updateTimeout = 0.4
            let engine = try engine(
                script: """
                    function update() { return new Promise(function() {}); }
                    function render() { return { elements: [] }; }
                    """, limits: limits)
            try await engine.load()
            let started = Date()
            #expect(await failure { _ = try await engine.update(settings: [:]) } == .timedOut(.update, limit: 0.4))
            #expect(Date().timeIntervalSince(started) < 3)
        }

        @Test func rendersInABackgroundIsolationDomain() async throws {
            let engine = try engine(script: "function render() { return { elements: [] }; }")
            try await engine.load()
            // Many renders in a row, from several tasks, serialize on the actor without tripping.
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0 ..< 8 {
                    group.addTask { _ = try await engine.render(settings: [:]) }
                }
                try await group.waitForAll()
            }
        }
    }

    /// Collects log lines from the engine's sink, which may be called off the test's task.
    private final class LogSink: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []

        func append(_ line: String) {
            lock.withLock { lines.append(line) }
        }

        var all: [String] { lock.withLock { lines } }
    }
#endif
