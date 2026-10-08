import AppKit
import DockCore

/// Tells when the user switches to an app, for the dock's recent apps section. Only
/// regular apps count (ones that show in the Dock, not menu bar agents). Nothing is
/// observed while there's no handler.
@MainActor
public final class AppActivationMonitor {
    /// Called with each app as it becomes active.
    public var onActivate: ((AppItem) -> Void)? {
        didSet { update() }
    }

    private var observer: (any NSObjectProtocol)?

    public init() {}

    isolated deinit {
        stopObserving()
    }

    private func update() {
        if onActivate == nil {
            stopObserving()
        } else if observer == nil {
            observe()
        }
    }

    private func observe() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let activated = ActivatedApp(note) else { return }
            MainActor.assumeIsolated { self?.onActivate?(activated.app) }
        }
    }

    private func stopObserving() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }
}

/// The activated app as an `AppItem`, read where the notification is posted.
private struct ActivatedApp: Sendable {
    let app: AppItem

    init?(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            app.activationPolicy == .regular,
            let url = app.bundleURL
        else { return nil }
        self.app = AppItem(url: url, bundleIdentifier: app.bundleIdentifier)
    }
}
