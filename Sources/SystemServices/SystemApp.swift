import AppKit
import Foundation

/// An app that ships with macOS and that a widget's popover opens ("Open Calendar"). Found
/// through Launch Services by bundle identifier, so an app the user moved still opens, and
/// one that isn't on this Mac shows up as `isInstalled == false` (a disabled button) rather
/// than a click that does nothing. The stock path is the fallback for a Launch Services
/// database that doesn't list the app.
public enum SystemApp: String, CaseIterable, Sendable {
    case calendar = "com.apple.iCal"
    case reminders = "com.apple.reminders"
    case weather = "com.apple.weather"
    case stocks = "com.apple.stocks"
    case shortcuts = "com.apple.shortcuts"
    case activityMonitor = "com.apple.ActivityMonitor"

    public var bundleIdentifier: String { rawValue }

    /// Where the app ships in macOS.
    public var defaultPath: String {
        switch self {
        case .calendar: "/System/Applications/Calendar.app"
        case .reminders: "/System/Applications/Reminders.app"
        case .weather: "/System/Applications/Weather.app"
        case .stocks: "/System/Applications/Stocks.app"
        case .shortcuts: "/System/Applications/Shortcuts.app"
        case .activityMonitor: "/System/Applications/Utilities/Activity Monitor.app"
        }
    }

    /// The app on this Mac, or nil when it's neither registered nor at its stock path.
    @MainActor
    public var url: URL? {
        Self.resolve(
            registered: NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
            defaultPath: defaultPath,
            exists: { FileManager.default.fileExists(atPath: $0) })
    }

    @MainActor
    public var isInstalled: Bool { url != nil }

    /// Opens the app, if it's installed.
    @MainActor
    public func open() {
        guard let url else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// What `url` returns: the registered location when Launch Services has one, else the
    /// stock path when something is there, else nil.
    static func resolve(registered: URL?, defaultPath: String, exists: (String) -> Bool) -> URL? {
        if let registered { return registered }
        return exists(defaultPath) ? URL(fileURLWithPath: defaultPath) : nil
    }
}
