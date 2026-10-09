import AppKit
import ApplicationServices
import Observation

/// What `AccessibilityPermission` asks of macOS. `SystemAccessibilityPermissionBackend` in
/// production; tests use a stand-in.
@MainActor
public protocol AccessibilityPermissionBackend: AnyObject {
    /// Whether the user has allowed OpenDock under Privacy & Security > Accessibility.
    var isTrusted: Bool { get }
    /// Shows macOS's prompt to allow Accessibility access. macOS shows it once per app;
    /// after the user has answered, calling it again does nothing.
    func promptForTrust()
    /// Opens Privacy & Security > Accessibility in System Settings.
    func openSystemSettings()
}

/// Whether macOS lets OpenDock use Accessibility, for every feature that needs it: the
/// windows in an app's menu, click-to-minimize, and badges read from Apple's Dock.
///
/// One instance is shared by all of them, so they agree on the answer, the user is asked
/// once, and Settings shows the permission in one place. It is only ever requested when the
/// user turns one of those features on or asks for it (`request()`), never at launch.
/// macOS doesn't tell an app when the user changes the setting, so `refresh()` reads it
/// again; features call it before they use Accessibility, and Settings when the app comes
/// back to the front.
@MainActor
@Observable
public final class AccessibilityPermission {
    /// Whether OpenDock has Accessibility access, as of the last check.
    public private(set) var isGranted: Bool

    @ObservationIgnored private let backend: any AccessibilityPermissionBackend
    @ObservationIgnored private var hasPrompted = false

    public init(backend: any AccessibilityPermissionBackend = SystemAccessibilityPermissionBackend()) {
        self.backend = backend
        isGranted = backend.isTrusted
    }

    /// Reads the permission again and returns it.
    @discardableResult
    public func refresh() -> Bool {
        let granted = backend.isTrusted
        if granted != isGranted { isGranted = granted }
        return granted
    }

    /// Asks for access: with macOS's prompt the first time, then by opening System
    /// Settings, because macOS doesn't prompt again once the user has answered.
    public func request() {
        guard !refresh() else { return }
        if hasPrompted {
            backend.openSystemSettings()
        } else {
            hasPrompted = true
            backend.promptForTrust()
            refresh()
        }
    }

    /// Records that macOS refused an Accessibility call, which means access was taken away.
    public func noteDenied() {
        if isGranted { isGranted = false }
    }
}

/// The real permission, through `AXIsProcessTrusted`.
@MainActor
public final class SystemAccessibilityPermissionBackend: AccessibilityPermissionBackend {
    public init() {}

    public var isTrusted: Bool { AXIsProcessTrusted() }

    public func promptForTrust() {
        // The value of `kAXTrustedCheckOptionPrompt`, a mutable global strict concurrency rejects.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public func openSystemSettings() {
        SystemSettingsPane.accessibility.open()
    }
}
