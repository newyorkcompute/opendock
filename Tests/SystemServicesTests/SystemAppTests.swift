import Foundation
import Testing

@testable import SystemServices

@Suite("System apps")
struct SystemAppTests {
    /// The identifiers and stock paths of Apple's apps; pinned so a typo can't turn a
    /// button into a no-op.
    @Test func identifiersAndPathsAreTheKnownOnes() {
        let expected: [SystemApp: (bundleIdentifier: String, path: String)] = [
            .calendar: ("com.apple.iCal", "/System/Applications/Calendar.app"),
            .reminders: ("com.apple.reminders", "/System/Applications/Reminders.app"),
            .weather: ("com.apple.weather", "/System/Applications/Weather.app"),
            .stocks: ("com.apple.stocks", "/System/Applications/Stocks.app"),
            .shortcuts: ("com.apple.shortcuts", "/System/Applications/Shortcuts.app"),
            .activityMonitor: ("com.apple.ActivityMonitor", "/System/Applications/Utilities/Activity Monitor.app"),
        ]
        #expect(Set(expected.keys) == Set(SystemApp.allCases))
        for (app, known) in expected {
            #expect(app.bundleIdentifier == known.bundleIdentifier)
            #expect(app.defaultPath == known.path)
            #expect(app.defaultPath.hasSuffix(".app"))
        }
    }

    @Test func theRegisteredLocationWinsOverTheStockPath() {
        let moved = URL(fileURLWithPath: "/Applications/Moved/Calendar.app")
        let resolved = SystemApp.resolve(registered: moved, defaultPath: "/System/Applications/Calendar.app") { _ in
            true
        }
        #expect(resolved == moved)
    }

    @Test func fallsBackToTheStockPathOnlyWhenSomethingIsThere() {
        let path = "/System/Applications/Calendar.app"
        var asked: [String] = []
        let present = SystemApp.resolve(registered: nil, defaultPath: path) { candidate in
            asked.append(candidate)
            return true
        }
        #expect(present == URL(fileURLWithPath: path))
        #expect(asked == [path])

        let missing = SystemApp.resolve(registered: nil, defaultPath: path) { _ in false }
        #expect(missing == nil)
    }
}
