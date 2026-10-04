import AppKit
import DockCore
import Observation

/// Tracks which applications are running and which is frontmost, by bundle URL
/// and bundle identifier. Observed by the dock to draw running indicators.
@MainActor
@Observable
public final class RunningAppsMonitor {
    public struct Snapshot: Sendable, Equatable {
        public var runningBundleIDs: Set<String> = []
        /// Normalized bundle paths (see `URL.normalizedPath`).
        public var runningBundlePaths: Set<String> = []
        public var frontmostBundleID: String?
        /// Running GUI apps that aren't hidden from the Dock (activationPolicy == .regular).
        public var regularApps: [AppDescriptor] = []
    }

    /// Minimal, Sendable description of a running app.
    public struct AppDescriptor: Sendable, Hashable, Identifiable {
        public var id: pid_t { processIdentifier }
        public let processIdentifier: pid_t
        public let bundleIdentifier: String?
        public let bundleURL: URL?
        public let localizedName: String?
    }

    public private(set) var snapshot = Snapshot()

    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private let workspace = NSWorkspace.shared

    public init() {
        refresh()
        let center = workspace.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append(token)
        }
    }

    isolated deinit {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
    }

    public func refresh() {
        var next = Snapshot()
        for app in workspace.runningApplications where app.activationPolicy == .regular {
            if let id = app.bundleIdentifier { next.runningBundleIDs.insert(id) }
            if let url = app.bundleURL { next.runningBundlePaths.insert(url.normalizedPath) }
            next.regularApps.append(AppDescriptor(
                processIdentifier: app.processIdentifier,
                bundleIdentifier: app.bundleIdentifier,
                bundleURL: app.bundleURL?.standardizedFileURL,
                localizedName: app.localizedName
            ))
        }
        next.frontmostBundleID = workspace.frontmostApplication?.bundleIdentifier
        if next != snapshot { snapshot = next }
    }

    // MARK: Queries

    public func isRunning(bundleIdentifier: String?, bundleURL: URL) -> Bool {
        if let bundleIdentifier, snapshot.runningBundleIDs.contains(bundleIdentifier) { return true }
        return snapshot.runningBundlePaths.contains(bundleURL.normalizedPath)
    }

    public func isFrontmost(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return snapshot.frontmostBundleID == bundleIdentifier
    }

    public func runningApplication(bundleIdentifier: String?, bundleURL: URL) -> NSRunningApplication? {
        workspace.runningApplications.first { app in
            if let bundleIdentifier, app.bundleIdentifier == bundleIdentifier { return true }
            return app.bundleURL?.normalizedPath == bundleURL.normalizedPath
        }
    }
}
