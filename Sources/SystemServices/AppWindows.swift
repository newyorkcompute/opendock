import AppKit
import ApplicationServices
import Observation
import os

/// One of a running app's windows, as the Accessibility API describes it.
public struct AppWindow: Identifiable, Hashable, Sendable {
    /// Identifies the window to its `WindowBackend` until the next listing.
    public let id: Int
    /// Empty for untitled windows.
    public var title: String
    public var isMinimized: Bool
    /// The window the app considers current: the one it brings forward when activated.
    public var isMain: Bool

    public init(id: Int, title: String, isMinimized: Bool, isMain: Bool) {
        self.id = id
        self.title = title
        self.isMinimized = isMinimized
        self.isMain = isMain
    }
}

/// Everything `AppWindowManager` asks of the system. `SystemWindowBackend` in production.
@MainActor
public protocol WindowBackend: AnyObject {
    /// Whether the user has given OpenDock Accessibility access.
    var isTrusted: Bool { get }
    /// Shows macOS's prompt to allow Accessibility access.
    func promptForTrust()
    /// Opens Privacy & Security > Accessibility in System Settings.
    func openAccessibilitySettings()
    /// The app's standard windows (documents, browser windows; not panels or dialogs),
    /// front to back, minimized ones included. Ids from earlier listings stop working.
    func windows(ofProcess processIdentifier: pid_t) -> [AppWindow]
    func setMinimized(_ minimized: Bool, window: AppWindow.ID)
    /// Puts the window in front of the app's other windows and makes it the main one.
    func raise(_ window: AppWindow.ID)
    /// Makes the app frontmost, bringing forward only its front window.
    func activate(processIdentifier: pid_t)
}

/// Lists and arranges other apps' windows for the dock: the windows in an app's menu, and
/// minimizing on click. Both need Accessibility access, which is only asked for when the
/// user wants one of them (`requestAccess`), never at launch.
@MainActor
@Observable
public final class AppWindowManager {
    /// What clicking the frontmost app's icon did with click-to-minimize on.
    public enum ToggleOutcome: Hashable, Sendable {
        case minimized
        case restored
    }

    /// Whether OpenDock has Accessibility access, as of the last check.
    public private(set) var isTrusted: Bool

    @ObservationIgnored private let backend: any WindowBackend
    @ObservationIgnored private var hasPrompted = false

    public init(backend: any WindowBackend = SystemWindowBackend()) {
        self.backend = backend
        isTrusted = backend.isTrusted
    }

    /// Checks for Accessibility access again. The user grants it in System Settings, which
    /// doesn't tell the app.
    @discardableResult
    public func refreshTrust() -> Bool {
        let trusted = backend.isTrusted
        if trusted != isTrusted { isTrusted = trusted }
        return trusted
    }

    /// Asks for Accessibility access: with macOS's prompt the first time, then by opening
    /// System Settings, because macOS doesn't prompt again once the user has answered.
    public func requestAccess() {
        guard !refreshTrust() else { return }
        if hasPrompted {
            backend.openAccessibilitySettings()
        } else {
            hasPrompted = true
            backend.promptForTrust()
        }
    }

    /// The windows to list in an app's menu, sorted by title like the Dock's menu. Empty
    /// without Accessibility access.
    public func menuWindows(ofProcess processIdentifier: pid_t) -> [AppWindow] {
        guard refreshTrust() else { return [] }
        return backend.windows(ofProcess: processIdentifier).sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    /// Brings `window` to the front, restoring it first if it's minimized.
    public func bringToFront(_ window: AppWindow, ofProcess processIdentifier: pid_t) {
        guard refreshTrust() else { return }
        if window.isMinimized { backend.setMinimized(false, window: window.id) }
        backend.raise(window.id)
        backend.activate(processIdentifier: processIdentifier)
    }

    /// Click-to-minimize, for a click on the frontmost app: minimizes its windows, or
    /// restores them when they're all minimized already. Returns nil when it can't do
    /// either (no access, or no windows), and the click should open the app as usual.
    public func toggleMinimized(ofProcess processIdentifier: pid_t) -> ToggleOutcome? {
        guard refreshTrust() else { return nil }
        let windows = backend.windows(ofProcess: processIdentifier)
        let visible = windows.filter { !$0.isMinimized }
        if !visible.isEmpty {
            for window in visible { backend.setMinimized(true, window: window.id) }
            return .minimized
        }
        guard let front = windows.first(where: \.isMain) ?? windows.first else { return nil }
        for window in windows { backend.setMinimized(false, window: window.id) }
        backend.raise(front.id)
        backend.activate(processIdentifier: processIdentifier)
        return .restored
    }
}

// MARK: - System backend

/// Reads and arranges windows through `AXUIElement`, which needs the user to allow
/// OpenDock in System Settings > Privacy & Security > Accessibility.
@MainActor
public final class SystemWindowBackend: WindowBackend {
    private var elements: [AppWindow.ID: AXUIElement] = [:]
    private var nextID = 0
    private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "AppWindows")

    public init() {
        // The dock waits for these calls. An app that has stopped responding would
        // otherwise hold it up for the default of about six seconds.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1)
    }

    public var isTrusted: Bool { AXIsProcessTrusted() }

    public func promptForTrust() {
        // `kAXTrustedCheckOptionPrompt` is this key; the imported constant isn't concurrency-safe.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public func openAccessibilitySettings() {
        guard
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    public func windows(ofProcess processIdentifier: pid_t) -> [AppWindow] {
        elements = [:]
        let app = AXUIElementCreateApplication(processIdentifier)
        guard let windows: [AXUIElement] = app.value(of: kAXWindowsAttribute) else { return [] }
        return windows.compactMap { element in
            guard element.value(of: kAXSubroleAttribute) == kAXStandardWindowSubrole else { return nil }
            nextID += 1
            elements[nextID] = element
            return AppWindow(
                id: nextID,
                title: element.value(of: kAXTitleAttribute) ?? "",
                isMinimized: element.value(of: kAXMinimizedAttribute) ?? false,
                isMain: element.value(of: kAXMainAttribute) ?? false
            )
        }
    }

    public func setMinimized(_ minimized: Bool, window: AppWindow.ID) {
        guard let element = elements[window] else { return }
        set(kAXMinimizedAttribute, to: minimized, on: element)
    }

    public func raise(_ window: AppWindow.ID) {
        guard let element = elements[window] else { return }
        set(kAXMainAttribute, to: true, on: element)
        let error = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        if error != .success { log.debug("Couldn't raise a window: AXError \(error.rawValue)") }
    }

    public func activate(processIdentifier: pid_t) {
        // Unlike `NSRunningApplication.activate`, which macOS may refuse to a background
        // app like the dock.
        set(kAXFrontmostAttribute, to: true, on: AXUIElementCreateApplication(processIdentifier))
    }

    private func set(_ attribute: String, to value: Bool, on element: AXUIElement) {
        let error = AXUIElementSetAttributeValue(element, attribute as CFString, value as CFTypeRef)
        if error != .success {
            log.debug("Couldn't set \(attribute, privacy: .public): AXError \(error.rawValue)")
        }
    }
}

private extension AXUIElement {
    func value<Value>(of attribute: String) -> Value? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value as? Value
    }
}
