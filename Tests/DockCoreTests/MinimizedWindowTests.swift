import Foundation
import Testing

@testable import DockCore

@Suite("Minimized windows")
struct MinimizedWindowTests {
    private let mail = AppItem(
        url: URL(fileURLWithPath: "/Applications/Mail.app"), bundleIdentifier: "com.apple.mail")
    private let safari = AppItem(
        url: URL(fileURLWithPath: "/Applications/Safari.app"), bundleIdentifier: "com.apple.Safari")

    private func window(
        _ id: Int, _ title: String, app: AppItem? = nil, pid: Int32 = 10
    ) -> MinimizedDockWindow {
        MinimizedDockWindow(
            id: MinimizedDockWindow.ID(windowID: id),
            processIdentifier: pid,
            title: title,
            app: app ?? mail
        )
    }

    // MARK: - Labels

    @Test func labelIsTheTitleOrTheAppName() {
        #expect(window(1, "Inbox").label == "Inbox")
        #expect(window(1, "  ").label == "Mail")
        #expect(window(1, "").label == "Mail")
    }

    // MARK: - Section

    @Test func sectionIsHiddenWhenTheSettingIsOffOrThereAreNoWindows() {
        let windows = [window(1, "Inbox")]
        #expect(!MinimizedWindowSection.isVisible(showMinimizedWindows: false, windows: windows))
        #expect(!MinimizedWindowSection.isVisible(showMinimizedWindows: true, windows: []))
        #expect(MinimizedWindowSection.isVisible(showMinimizedWindows: true, windows: windows))
        #expect(
            MinimizedWindowSection.displayed(
                reported: windows, previouslyShown: windows, showMinimizedWindows: false
            ).isEmpty)
    }

    // MARK: - Order and identity

    @Test func oneItemPerWindowIDKeepingTheLatestReport() {
        let reported = [
            window(7, "Inbox"),
            window(7, "Inbox (2)", pid: 11),
            window(8, "Sent"),
        ]
        let shown = MinimizedWindowSection.ordered(reported: reported)
        #expect(shown.map(\.id.windowID) == [7, 8])
        #expect(shown[0].title == "Inbox (2)")
        #expect(shown[0].processIdentifier == 11)
    }

    @Test func windowsAlreadyShownKeepTheirPlacesAndNewOnesAppend() {
        let previous = [window(1, "One"), window(2, "Two")]
        let reported = [
            window(3, "Three", app: safari, pid: 20),
            window(2, "Two renamed"),
            window(1, "One"),
        ]
        let shown = MinimizedWindowSection.ordered(reported: reported, previouslyShown: previous)
        #expect(shown.map(\.id.windowID) == [1, 2, 3])
        #expect(shown.map(\.title) == ["One", "Two renamed", "Three"])
        #expect(shown[2].app.bundleIdentifier == "com.apple.Safari")
    }

    @Test func aRestoredWindowLeavesAndDoesNotComeBackInTheMiddle() {
        let previous = [window(1, "One"), window(2, "Two"), window(3, "Three")]
        let shown = MinimizedWindowSection.ordered(
            reported: [window(3, "Three"), window(1, "One")],
            previouslyShown: previous
        )
        #expect(shown.map(\.id.windowID) == [1, 3])
    }

    @Test func duplicateEntriesAlreadyOnTheDockAreShownOnce() {
        let previous = [window(4, "Draft"), window(4, "Draft again"), window(5, "Notes")]
        let shown = MinimizedWindowSection.ordered(
            reported: [window(5, "Notes"), window(4, "Draft")],
            previouslyShown: previous
        )
        #expect(shown.map(\.id.windowID) == [4, 5])
        #expect(shown.map(\.title) == ["Draft", "Notes"])
    }

    @Test func aFreshReportOrdersWindowsAsFirstReported() {
        let shown = MinimizedWindowSection.ordered(reported: [
            window(9, "Later"),
            window(2, "Earlier"),
            window(9, "Later still"),
        ])
        #expect(shown.map(\.id.windowID) == [9, 2])
        #expect(shown[0].title == "Later still")
    }
}
