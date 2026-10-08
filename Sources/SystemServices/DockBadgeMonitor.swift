import AppKit
import DockCore
import Observation

/// The badge Apple's Dock shows on one app's tile: an unread count, a dot, or a short word.
public struct DockBadge: Hashable, Sendable {
    public var label: String
    /// The tile's title, the app's name.
    public var title: String?
    /// Where the app's bundle is.
    public var bundleURL: URL?
    public var bundleIdentifier: String?

    public init(label: String, title: String? = nil, bundleURL: URL? = nil, bundleIdentifier: String? = nil) {
        self.label = label
        self.title = title
        self.bundleURL = bundleURL?.standardizedFileURL
        self.bundleIdentifier = bundleIdentifier
    }

    /// The accessibility subrole of an app's tile in Apple's Dock. Folders, the Trash,
    /// minimized windows, and separators have other subroles.
    public static let applicationTileSubrole = "AXApplicationDockItem"

    /// The badge on a tile of Apple's Dock, from the tile's accessibility attributes, or nil
    /// if the tile isn't an app's or shows no badge.
    public init?(
        subrole: String?,
        statusLabel: String?,
        url: URL?,
        title: String?,
        bundleIdentifier: String? = nil
    ) {
        guard subrole == Self.applicationTileSubrole,
            let label = statusLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
            !label.isEmpty
        else { return nil }
        self.init(label: label, title: title, bundleURL: url, bundleIdentifier: bundleIdentifier)
    }
}

/// The badges Apple's Dock shows, looked up by app.
public struct DockBadges: Equatable, Sendable {
    public private(set) var all: [DockBadge]
    private var byBundleIdentifier: [String: String] = [:]
    private var byPath: [String: String] = [:]
    private var byTitle: [String: String] = [:]

    public init(_ badges: [DockBadge] = []) {
        all = badges
        for badge in badges {
            if let id = badge.bundleIdentifier { byBundleIdentifier[id] = badge.label }
            if let url = badge.bundleURL {
                byPath[url.normalizedPath] = badge.label
                byPath[url.resolvingSymlinksInPath().normalizedPath] = badge.label
            } else if badge.bundleIdentifier == nil, let title = badge.title {
                // Only a tile Apple's Dock gives no location for is matched by name.
                byTitle[title.lowercased()] = badge.label
            }
        }
    }

    public var isEmpty: Bool { all.isEmpty }

    /// The label of `app`'s badge, matched by bundle identifier, then bundle location, then name.
    public func label(for app: AppItem) -> String? {
        if let id = app.bundleIdentifier, let label = byBundleIdentifier[id] { return label }
        if let label = byPath[app.url.normalizedPath] { return label }
        return byTitle[app.displayName.lowercased()]
    }

    public static func == (lhs: DockBadges, rhs: DockBadges) -> Bool { lhs.all == rhs.all }
}

/// Why badges couldn't be read.
public enum DockBadgeReadError: Error, Equatable, Sendable {
    /// macOS doesn't let OpenDock use Accessibility.
    case accessDenied
    /// Apple's Dock isn't running, for instance while it restarts.
    case dockNotRunning
    /// Apple's Dock didn't answer, or answered with something unexpected.
    case failed
}

/// Where badges come from. `AccessibilityDockBadgeSource` reads them from Apple's Dock;
/// tests use a stand-in.
@MainActor
public protocol DockBadgeSource: AnyObject {
    /// The badges Apple's Dock shows now. Throws a `DockBadgeReadError`.
    func readBadges() async throws -> [DockBadge]
}

/// Keeps the badges of running apps up to date while the dock is on screen.
///
/// macOS has no public API for other apps' badges, and Accessibility can't notify when one
/// changes, so the badges are read from Apple's Dock every `pollInterval`, and again soon
/// after an app is activated or quits (when badges tend to change). Nothing is read while
/// badges are turned off or the dock is hidden. Without Accessibility access
/// (`permission`), only the access itself is checked, every `accessCheckInterval`; reading
/// starts as soon as it's granted.
@MainActor
@Observable
public final class DockBadgeMonitor {
    public private(set) var badges = DockBadges()

    /// The Accessibility permission the badges are read with, shared with everything else
    /// that needs it.
    public let permission: AccessibilityPermission

    /// The user's setting. Turning it off clears the badges.
    @ObservationIgnored public var isEnabled = false {
        didSet { if isEnabled != oldValue { update() } }
    }

    /// Whether the dock is on screen. Badges aren't read while it's auto-hidden, and are
    /// read right away when it comes back.
    @ObservationIgnored public var isDockVisible = true {
        didSet { if isDockVisible != oldValue { update() } }
    }

    public static let pollInterval = Duration.seconds(2)
    public static let accessCheckInterval = Duration.seconds(5)
    /// How long after an app is activated or quits to read the badges again.
    static let appChangeDelay = Duration.milliseconds(300)

    @ObservationIgnored private let source: any DockBadgeSource
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    /// Counts the times polling has started, so a stale permission observation can tell it
    /// has nothing to restart.
    @ObservationIgnored private var pollingGeneration = 0

    public init(source: any DockBadgeSource, permission: AccessibilityPermission) {
        self.source = source
        self.permission = permission
    }

    isolated deinit {
        pollTask?.cancel()
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
    }

    /// The label of `app`'s badge, if it shows one.
    public func label(for app: AppItem) -> String? {
        badges.label(for: app)
    }

    /// Reads the badges once, if they're wanted now. Returns how long to wait before the
    /// next read.
    @discardableResult
    public func refresh() async -> Duration {
        guard isEnabled, isDockVisible else { return Self.pollInterval }
        guard permission.refresh() else { return Self.accessCheckInterval }
        do {
            let read = try await source.readBadges()
            // Turned off, hidden, or superseded by a newer read while this one ran.
            guard !Task.isCancelled, isEnabled, isDockVisible else { return Self.pollInterval }
            setBadges(DockBadges(read))
        } catch DockBadgeReadError.accessDenied {
            permission.noteDenied()
            setBadges(DockBadges())
            return Self.accessCheckInterval
        } catch {
            if !Task.isCancelled { setBadges(DockBadges()) }
        }
        return Self.pollInterval
    }

    // MARK: - Polling

    private func setBadges(_ new: DockBadges) {
        if new != badges { badges = new }
    }

    private func update() {
        if !isEnabled { setBadges(DockBadges()) }
        if isEnabled, isDockVisible {
            observeApps()
            restartPolling()
            watchPermission(generation: pollingGeneration)
        } else {
            pollTask?.cancel()
            pollTask = nil
            stopObservingApps()
        }
    }

    /// Reads right away when the permission changes (granted in System Settings, say),
    /// instead of at the next access check, for as long as this round of polling lasts.
    private func watchPermission(generation: Int) {
        _ = withObservationTracking {
            permission.isGranted
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, pollTask != nil, generation == pollingGeneration else { return }
                restartPolling()
                watchPermission(generation: generation)
            }
        }
    }

    /// Reads now (or after `delay`), then every `pollInterval`.
    private func restartPolling(after delay: Duration = .zero) {
        pollTask?.cancel()
        if pollTask == nil { pollingGeneration += 1 }
        pollTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            while !Task.isCancelled {
                guard let interval = await self?.refresh() else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func observeApps() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didTerminateApplicationNotification]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restartPolling(after: Self.appChangeDelay) }
            }
        }
    }

    private func stopObservingApps() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers = []
    }
}
