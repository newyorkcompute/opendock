import Foundation
import Observation
import ServiceManagement

/// Observable wrapper around `SMAppService.mainApp`.
///
/// Registration only works from inside a signed `.app` bundle. When OpenDock runs as
/// a bare binary (e.g. `swift run`), `register()` throws; the error is surfaced through
/// `errorMessage` rather than crashing.
@Observable
final class LaunchAtLogin {
    private(set) var status: SMAppService.Status
    /// Human-readable description of the last failed register/unregister, if any.
    private(set) var errorMessage: String?

    @ObservationIgnored private let service = SMAppService.mainApp

    init() {
        status = service.status
    }

    /// On when registered, including while waiting for the user's approval.
    var isEnabled: Bool {
        get { status == .enabled || status == .requiresApproval }
        set { setEnabled(newValue) }
    }

    /// The user has to allow OpenDock in System Settings > General > Login Items.
    var requiresApproval: Bool { status == .requiresApproval }

    /// False when running outside an app bundle, where login items can't be registered.
    var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    /// Re-reads the status; the user can change it in System Settings at any time.
    func refresh() {
        status = service.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
