import CoreGraphics
import Observation

/// What `ScreenRecordingPermission` asks of macOS. `SystemScreenRecordingPermissionBackend`
/// in production; tests use a stand-in.
@MainActor
public protocol ScreenRecordingPermissionBackend: AnyObject {
    /// Whether Screen Recording is already allowed. Checking must not prompt.
    var isGranted: Bool { get }
    /// Shows macOS's prompt to allow Screen Recording. Only called when the user asks
    /// for it in Settings.
    func prompt()
    /// Opens Privacy & Security > Screen Recording in System Settings.
    func openSystemSettings()
}

/// Whether macOS lets OpenDock capture window thumbnails.
///
/// Minimized windows in the dock use a thumbnail only when this is already granted.
/// Nothing here prompts on its own: `refresh()` reads the current answer, and `request()`
/// is the Settings button. macOS doesn't tell an app when the user changes the setting,
/// so callers `refresh()` when the app comes back to the front.
@MainActor
@Observable
public final class ScreenRecordingPermission {
    /// Whether OpenDock has Screen Recording access, as of the last check.
    public private(set) var isGranted: Bool

    @ObservationIgnored private let backend: any ScreenRecordingPermissionBackend
    @ObservationIgnored private var hasPrompted = false

    public init(backend: any ScreenRecordingPermissionBackend = SystemScreenRecordingPermissionBackend()) {
        self.backend = backend
        isGranted = backend.isGranted
    }

    /// Reads the permission again and returns it. Does not prompt.
    @discardableResult
    public func refresh() -> Bool {
        let granted = backend.isGranted
        if granted != isGranted { isGranted = granted }
        return granted
    }

    /// Asks for access, because the user chose it in Settings: with macOS's prompt the
    /// first time, then by opening System Settings, because macOS doesn't prompt again
    /// once the user has answered.
    public func request() {
        guard !refresh() else { return }
        if hasPrompted {
            backend.openSystemSettings()
        } else {
            hasPrompted = true
            backend.prompt()
            refresh()
        }
    }
}

/// The real permission, through `CGPreflightScreenCaptureAccess`, which does not prompt.
@MainActor
public final class SystemScreenRecordingPermissionBackend: ScreenRecordingPermissionBackend {
    public init() {}

    public var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    public func prompt() {
        _ = CGRequestScreenCaptureAccess()
    }

    public func openSystemSettings() {
        SystemSettingsPane.screenRecording.open()
    }
}
