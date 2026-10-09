import DockCore
import Foundation
import Testing

@testable import SystemServices

/// A scripted `shortcuts` tool: answers `list` with fixed names and `run` per shortcut.
private final class FakeShortcutsTool: ShortcutsCommandRunner, @unchecked Sendable {
    let isAvailable: Bool
    var listOutput: String
    var runResults: [String: ShortcutsCommandResult]
    /// Set to pretend the tool can't be launched at all.
    var failsToLaunch = false
    private(set) var invocations: [[String]] = []
    private let lock = NSLock()

    init(isAvailable: Bool = true, listOutput: String = "", runResults: [String: ShortcutsCommandResult] = [:]) {
        self.isAvailable = isAvailable
        self.listOutput = listOutput
        self.runResults = runResults
    }

    func run(_ arguments: [String], timeout: TimeInterval) async -> ShortcutsCommandResult? {
        lock.withLock { invocations.append(arguments) }
        if failsToLaunch { return nil }
        switch arguments.first {
        case "list":
            return ShortcutsCommandResult(exitStatus: 0, standardOutput: listOutput)
        case "run":
            let name = arguments.dropFirst().first ?? ""
            return runResults[name]
                ?? ShortcutsCommandResult(exitStatus: 1, standardError: "Error: Shortcut not found.")
        default:
            return ShortcutsCommandResult(exitStatus: 64, standardError: "unknown command")
        }
    }
}

@MainActor
@Suite("Shortcuts service")
struct ShortcutsServiceTests {
    @Test func listsShortcutsOnRefresh() async {
        let tool = FakeShortcutsTool(listOutput: "Start Focus\nLog Water\n")
        let service = ShortcutsService(runner: tool)
        #expect(!service.hasLoaded)
        #expect(service.exists("Start Focus") == nil)

        await service.refresh()

        #expect(service.hasLoaded)
        #expect(service.isAvailable)
        #expect(service.shortcuts == ["Start Focus", "Log Water"])
        #expect(service.exists("Start Focus") == true)
        #expect(service.exists("Gone") == false)
        #expect(tool.invocations == [["list"]])
    }

    @Test func refreshesAreThrottledUnlessForced() async {
        let tool = FakeShortcutsTool(listOutput: "A")
        let service = ShortcutsService(runner: tool)
        await service.refresh()
        await service.refresh()
        #expect(tool.invocations.count == 1)
        await service.refresh(force: true)
        #expect(tool.invocations.count == 2)
    }

    @Test func aMissingToolIsReported() async {
        let tool = FakeShortcutsTool(isAvailable: false)
        tool.failsToLaunch = true
        let service = ShortcutsService(runner: tool)
        #expect(!service.isAvailable)

        await service.refresh()
        #expect(service.hasLoaded)
        #expect(!service.isAvailable)
        #expect(service.shortcuts.isEmpty)

        let failure = await service.run("Anything")
        #expect(failure == .toolUnavailable)
        #expect(service.state(of: "Anything")?.failure == .toolUnavailable)
    }

    @Test func aSuccessfulRunIsRecorded() async {
        let tool = FakeShortcutsTool(runResults: ["Start Focus": ShortcutsCommandResult(exitStatus: 0)])
        let service = ShortcutsService(runner: tool)

        let failure = await service.run("Start Focus")

        #expect(failure == nil)
        #expect(tool.invocations == [["run", "Start Focus"]])
        guard case .succeeded = service.state(of: "Start Focus") else {
            Issue.record("expected a success, got \(String(describing: service.state(of: "Start Focus")))")
            return
        }
    }

    @Test func aFailedRunKeepsTheReason() async {
        let tool = FakeShortcutsTool(runResults: [
            "Broken": ShortcutsCommandResult(exitStatus: 1, standardError: "Error: The file couldn’t be opened."),
            "Slow": ShortcutsCommandResult(exitStatus: -1, timedOut: true),
        ])
        let service = ShortcutsService(runner: tool)

        #expect(await service.run("Broken") == .other("The file couldn’t be opened."))
        #expect(service.state(of: "Broken")?.failure == .other("The file couldn’t be opened."))
        #expect(await service.run("Slow") == .timedOut)
        #expect(await service.run("Nope") == .notFound)
        #expect(service.state(of: "Nope")?.statusText == "Shortcut not found")
    }

    @Test func blankNamesAndRepeatsAreIgnored() async {
        let tool = FakeShortcutsTool()
        let service = ShortcutsService(runner: tool)
        #expect(await service.run("   ") == .notFound)
        #expect(tool.invocations.isEmpty)
    }

    @Test func runsAreTrimmedAndClearable() async {
        let tool = FakeShortcutsTool(runResults: ["A": ShortcutsCommandResult(exitStatus: 0)])
        let service = ShortcutsService(runner: tool)
        await service.run("  A ")
        #expect(tool.invocations == [["run", "A"]])
        #expect(service.state(of: "A") != nil)
        service.clearState(of: "A")
        #expect(service.state(of: "A") == nil)
    }

    @Test func theRealToolLivesInUsrBin() {
        #expect(ShortcutsCommandLine.toolURL.path == "/usr/bin/shortcuts")
    }
}
