import Foundation
import Testing

@testable import SystemServices

@Suite("System Settings panes")
struct SystemSettingsPaneTests {
    /// These URL schemes aren't documented by Apple, so pin the ones known to work.
    @Test func urlsAreTheKnownWorkingOnes() {
        let expected: [SystemSettingsPane: String] = [
            .accessibility: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            .screenRecording: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            .automation: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
            .fullDiskAccess: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            .calendars: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
            .reminders: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders",
            .locationServices: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices",
            .battery: "x-apple.systempreferences:com.apple.Battery-Settings-extension",
            .network: "x-apple.systempreferences:com.apple.Network-Settings.extension",
        ]
        #expect(Set(expected.keys) == Set(SystemSettingsPane.allCases))
        for (pane, string) in expected {
            #expect(pane.url.absoluteString == string)
        }
    }

    @Test func everyPaneHasAParsableURL() {
        for pane in SystemSettingsPane.allCases {
            #expect(URL(string: "x-apple.systempreferences:" + pane.rawValue) != nil)
            #expect(pane.url.scheme == "x-apple.systempreferences")
        }
    }
}
