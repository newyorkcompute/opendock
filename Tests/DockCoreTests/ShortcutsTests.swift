import Foundation
import Testing

@testable import DockCore

@Suite("Shortcuts catalog")
struct ShortcutsCatalogTests {
    @Test func parsesOneNamePerLine() {
        let output = "Start Focus\nLog Water\nShut Down Everything\n"
        #expect(ShortcutsCatalog.names(fromListOutput: output) == ["Start Focus", "Log Water", "Shut Down Everything"])
    }

    @Test func dropsBlankLinesTrimsAndDeduplicates() {
        let output = "  Morning Routine \r\n\n\nMorning Routine\n   \nEvening\n"
        #expect(ShortcutsCatalog.names(fromListOutput: output) == ["Morning Routine", "Evening"])
    }

    @Test func emptyOutputMeansNoShortcuts() {
        #expect(ShortcutsCatalog.names(fromListOutput: "").isEmpty)
        #expect(ShortcutsCatalog.names(fromListOutput: "\n\n").isEmpty)
    }

    @Test func keepsTheToolsOrder() {
        #expect(ShortcutsCatalog.names(fromListOutput: "Zed\nalpha\nBeta") == ["Zed", "alpha", "Beta"])
    }

    @Test func filterIgnoresCaseAndDiacritics() {
        let names = ["Start Focus", "Café Timer", "Log Water", "focus off"]
        #expect(ShortcutsCatalog.filter(names, matching: "focus") == ["Start Focus", "focus off"])
        #expect(ShortcutsCatalog.filter(names, matching: "cafe") == ["Café Timer"])
        #expect(ShortcutsCatalog.filter(names, matching: "WATER") == ["Log Water"])
        #expect(ShortcutsCatalog.filter(names, matching: "nothing").isEmpty)
    }

    @Test func blankQueryMatchesEverything() {
        let names = ["A", "B"]
        #expect(ShortcutsCatalog.filter(names, matching: "") == names)
        #expect(ShortcutsCatalog.filter(names, matching: "   ") == names)
    }
}

@Suite("Shortcut history")
struct ShortcutHistoryTests {
    @Test func newestFirstAndCapped() {
        var names: [String] = []
        for index in 1 ... 10 {
            names = ShortcutHistory.adding("Shortcut \(index)", to: names)
        }
        #expect(names.count == ShortcutHistory.limit)
        #expect(names.first == "Shortcut 10")
        #expect(names.last == "Shortcut 3")
    }

    @Test func runningAgainMovesToTheFront() {
        let names = ShortcutHistory.adding("A", to: ["C", "B", "A"])
        #expect(names == ["A", "C", "B"])
    }

    @Test func blankNameChangesNothing() {
        #expect(ShortcutHistory.adding("", to: ["A"]) == ["A"])
        #expect(ShortcutHistory.adding("   ", to: ["A"]) == ["A"])
    }

    @Test func trimsAndHonorsLimit() {
        #expect(ShortcutHistory.adding("  X  ", to: ["A", "B"], limit: 2) == ["X", "A"])
        #expect(ShortcutHistory.adding("X", to: ["A"], limit: 0).isEmpty)
    }

    @Test func roundTripsThroughTheStoredString() {
        let names = ["Start Focus", "Log Water", "Shut Down Everything"]
        let stored = ShortcutHistory.stored(names)
        #expect(stored == "Start Focus\nLog Water\nShut Down Everything")
        #expect(ShortcutHistory.names(from: stored) == names)
        #expect(ShortcutHistory.names(from: "").isEmpty)
    }
}

@Suite("Shortcut run failures")
struct ShortcutRunFailureTests {
    @Test func cleanExitIsNotAFailure() {
        #expect(ShortcutRunFailure.interpret(exitStatus: 0, standardError: "") == nil)
        #expect(ShortcutRunFailure.interpret(exitStatus: 0, standardError: "some warning") == nil)
    }

    @Test func recognizesAMissingShortcut() {
        #expect(ShortcutRunFailure.interpret(exitStatus: 1, standardError: "Error: Shortcut not found.") == .notFound)
        #expect(
            ShortcutRunFailure.interpret(exitStatus: 1, standardError: "Couldn’t find the shortcut “X”.") == .notFound)
        #expect(ShortcutRunFailure.notFound.message == "Shortcut not found")
    }

    @Test func recognizesACancelledRun() {
        let failure = ShortcutRunFailure.interpret(
            exitStatus: 1, standardError: "Error: The operation was cancelled by the user.")
        #expect(failure == .cancelled)
        #expect(failure?.message == "Cancelled")
    }

    @Test func timingOutWinsOverTheExitStatus() {
        #expect(ShortcutRunFailure.interpret(exitStatus: 0, standardError: "", timedOut: true) == .timedOut)
        #expect(ShortcutRunFailure.interpret(exitStatus: -1, standardError: "x", timedOut: true) == .timedOut)
    }

    @Test func otherFailuresQuoteTheToolWithoutItsPrefix() {
        let failure = ShortcutRunFailure.interpret(
            exitStatus: 1, standardError: "\n  Error: The file couldn’t be opened.\nmore detail\n")
        #expect(failure == .other("The file couldn’t be opened."))
        #expect(failure?.message == "The file couldn’t be opened.")
    }

    @Test func silentFailuresReportTheExitStatus() {
        let failure = ShortcutRunFailure.interpret(exitStatus: 3, standardError: "   \n")
        #expect(failure == .other("Failed (exit status 3)"))
        #expect(ShortcutRunFailure.other("").message == "Failed")
    }

    @Test func firstMessageLineSkipsBlanksAndPrefixes() {
        #expect(ShortcutRunFailure.firstMessageLine(in: "") == "")
        #expect(ShortcutRunFailure.firstMessageLine(in: "\n\nerror: boom\nnext") == "boom")
        #expect(ShortcutRunFailure.firstMessageLine(in: "plain text") == "plain text")
    }
}

@Suite("Shortcut run state")
struct ShortcutRunStateTests {
    private let date = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func statusText() {
        #expect(ShortcutRunState.running(since: date).statusText == "Running…")
        #expect(ShortcutRunState.succeeded(at: date).statusText == "Done")
        #expect(ShortcutRunState.failed(.notFound, at: date).statusText == "Shortcut not found")
    }

    @Test func exposesItsParts() {
        let running = ShortcutRunState.running(since: date)
        #expect(running.isRunning)
        #expect(running.date == date)
        #expect(running.failure == nil)

        let failed = ShortcutRunState.failed(.timedOut, at: date)
        #expect(!failed.isRunning)
        #expect(failed.failure == .timedOut)
        #expect(ShortcutRunState.succeeded(at: date).failure == nil)
    }
}

@Suite("Shortcuts URLs")
struct ShortcutsURLTests {
    @Test func opensAndRunsByName() throws {
        let open = try #require(ShortcutsURL.open(name: "Start Focus"))
        #expect(open.scheme == "shortcuts")
        #expect(open.host == "open-shortcut")
        #expect(open.absoluteString == "shortcuts://open-shortcut?name=Start%20Focus")

        let run = try #require(ShortcutsURL.run(name: "Log Water"))
        #expect(run.absoluteString == "shortcuts://run-shortcut?name=Log%20Water")
    }

    @Test func escapesQueryDelimiters() throws {
        let url = try #require(ShortcutsURL.open(name: "Tea & Toast = Breakfast"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first?.value == "Tea & Toast = Breakfast")
        #expect(!url.absoluteString.contains("Tea & "))
    }

    @Test func createIsAFixedURL() {
        #expect(ShortcutsURL.create?.absoluteString == "shortcuts://create-shortcut")
    }
}

@Suite("Shortcut tile style")
struct ShortcutTileStyleTests {
    @Test func tintsAreUniqueLowercaseNames() {
        let names = ShortcutTint.allCases.map(\.rawValue)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { $0 == $0.lowercased() && !$0.isEmpty })
        #expect(ShortcutTint.allCases.contains(.default))
    }

    @Test func suggestedSymbolsAreUniqueAndIncludeTheDefault() {
        let symbols = ShortcutSymbols.suggested
        #expect(Set(symbols).count == symbols.count)
        #expect(symbols.contains(ShortcutSymbols.default))
        #expect(symbols.allSatisfy { !$0.isEmpty && !$0.contains(" ") })
    }
}
