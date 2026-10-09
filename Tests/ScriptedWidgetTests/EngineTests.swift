#if canImport(JavaScriptCore)
    import Foundation
    import ScriptedWidgetRuntime
    import Testing

    /// The JavaScriptCore engine, against the `hello` sample and small scripts written here.
    /// These only build where JavaScriptCore exists (macOS), which CI is.
    @Suite("Scripted widget engine")
    struct EngineTests {
        private static let noon = Date(timeIntervalSince1970: 1_760_000_000)

        private func engine(script: String, settings: String = "[]", limits: ScriptedWidgetLimits = .default) throws
            -> ScriptedWidgetEngine
        {
            let directory = try SampleWidget.makePackage(
                manifest: SampleWidget.manifest(settings: settings), script: script)
            return ScriptedWidgetEngine(package: try ScriptedWidgetPackage.load(from: directory), limits: limits)
        }

        private func failure(of body: () async throws(ScriptedWidgetError) -> Void) async -> ScriptedWidgetError? {
            do {
                try await body()
                return nil
            } catch {
                return error
            }
        }

        @Test func rendersTheHelloSample() async throws {
            let package = try ScriptedWidgetPackage.load(from: SampleWidget.directory)
            let engine = ScriptedWidgetEngine(package: package)
            try await engine.load()
            #expect(await engine.isLoaded)

            let tile = try await engine.render(settings: [:], now: Self.noon)
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
                settings: ["name": "Oslo", "showRing": "false", "refreshSeconds": "60"], now: Self.noon)
            #expect(second.refresh == 60)
            #expect(second.elements.count == 1)
            guard case let .column(again) = second.elements[0] else {
                Issue.record("unexpected elements \(second.elements)")
                return
            }
            #expect(again.children.first == .text(ScriptedText("Hello, Oslo")))
            #expect(again.children.last == .text(ScriptedText("Rendered 2×", style: .secondary)))

            let compact = try await engine.render(settings: [:], now: Self.noon, compact: true)
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
            let tile = try await engine.render(settings: ["count": "42", "flag": "false"], now: Self.noon)
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
            #expect(try await fine.render(settings: [:]).elements == [.text(ScriptedText("call 2"))])

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
            let tile = try await engine.render(settings: [:])
            #expect(tile.elements == [.text(ScriptedText("no undefined undefined undefined"))])
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
