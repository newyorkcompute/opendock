import AppKit
import Foundation

/// A pane of System Settings the app sends users to, usually to grant a permission it was
/// refused. Keeps the `x-apple.systempreferences:` URLs, which Apple doesn't document, in
/// one place.
public enum SystemSettingsPane: String, CaseIterable, Sendable {
    case accessibility = "com.apple.preference.security?Privacy_Accessibility"
    case automation = "com.apple.preference.security?Privacy_Automation"
    case fullDiskAccess = "com.apple.preference.security?Privacy_AllFiles"
    case calendars = "com.apple.preference.security?Privacy_Calendars"
    case reminders = "com.apple.preference.security?Privacy_Reminders"
    case locationServices = "com.apple.preference.security?Privacy_LocationServices"
    case battery = "com.apple.Battery-Settings-extension"
    case network = "com.apple.Network-Settings.extension"

    public var url: URL {
        // Every raw value is a valid URL path; this only fails on a typo in a new case.
        URL(string: "x-apple.systempreferences:" + rawValue)!
    }

    /// Opens the pane in System Settings.
    @MainActor
    public func open() {
        NSWorkspace.shared.open(url)
    }
}
