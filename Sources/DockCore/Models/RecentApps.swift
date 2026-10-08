import Foundation

/// The apps the user used most recently, newest first, for the dock's recent apps section
/// (like Apple's Dock and iPadOS). Pure bookkeeping: what counts as "used" is decided by
/// whoever calls `record`, and which of them the dock shows by `shown`.
///
/// Persisted in the document as a plain list of apps, so it survives a relaunch.
public struct RecentApps: Hashable, Sendable {
    /// How many apps are remembered. More than the dock can show, so that the ones hidden
    /// because they're running or pinned don't crowd out the others.
    public static let capacity = 20

    /// Newest first. No two entries are the same app.
    public private(set) var apps: [AppItem]

    public init(_ apps: [AppItem] = []) {
        self.apps = []
        for app in apps.reversed() { record(app) }
    }

    public var isEmpty: Bool { apps.isEmpty }

    /// `app` was used: it goes to the front, or moves there if it was already remembered (by
    /// bundle identifier or path, so an app that moved is still one app). Apps that no longer
    /// exist are forgotten at the same time. Returns whether anything changed.
    @discardableResult
    public mutating func record(_ app: AppItem, exists: (URL) -> Bool = { _ in true }) -> Bool {
        var updated = apps.filter { !$0.isSameApp(as: app) && exists($0.url) }
        updated.insert(app, at: 0)
        updated = Array(updated.prefix(Self.capacity))
        guard updated != apps else { return false }
        apps = updated
        return true
    }

    /// Forget `app` until it's used again. Returns whether it was remembered.
    @discardableResult
    public mutating func remove(_ app: AppItem) -> Bool {
        let before = apps.count
        apps.removeAll { $0.isSameApp(as: app) }
        return apps.count != before
    }

    /// The first `limit` remembered apps the dock has nowhere else: not pinned among `items`
    /// (by bundle identifier or path), not running (those are in the running section), and
    /// not the one with `ownBundleID` (OpenDock itself).
    public func shown(
        pinned items: [DockItem],
        runningBundleIDs: Set<String>,
        runningBundlePaths: Set<String>,
        excludingBundleID ownBundleID: String?,
        limit: Int
    ) -> [RecentDockApp] {
        guard limit > 0 else { return [] }
        let pinnedIDs = Set(items.compactMap { $0.appItem?.bundleIdentifier })
        let pinnedPaths = Set(items.compactMap { $0.appItem?.url.normalizedPath })
        let shown = apps.filter { app in
            if let bundleID = app.bundleIdentifier {
                if bundleID == ownBundleID || pinnedIDs.contains(bundleID) || runningBundleIDs.contains(bundleID) {
                    return false
                }
            }
            let path = app.url.normalizedPath
            return !pinnedPaths.contains(path) && !runningBundlePaths.contains(path)
        }
        return shown.prefix(limit).map { RecentDockApp(app: $0) }
    }
}

// MARK: - Codable

extension RecentApps: Codable {
    /// Stored as the bare list of apps.
    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode([AppItem].self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(apps)
    }
}

/// A recently used app that isn't pinned or running, shown after the running apps. Its
/// identity is where its bundle is, which is also how the list tells apps apart.
public struct RecentDockApp: Identifiable, Hashable, Sendable {
    public struct ID: Hashable, Sendable {
        public let path: String
    }

    public let app: AppItem

    public init(app: AppItem) {
        self.app = app
    }

    public var id: ID { ID(path: app.url.normalizedPath) }
}
