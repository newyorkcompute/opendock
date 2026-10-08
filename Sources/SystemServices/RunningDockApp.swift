import DockCore
import Foundation

/// A running app that isn't pinned, shown after the pinned items like in Apple's Dock.
/// It lasts as long as its process does and is never persisted.
public struct RunningDockApp: Identifiable, Hashable, Sendable {
    /// The same in every snapshot for as long as the process runs. The launch date tells
    /// a later process apart if the system hands it the same pid.
    public struct ID: Hashable, Sendable {
        public let processIdentifier: pid_t
        public let launchDate: Date?
    }

    public let id: ID
    public let app: AppItem
}

public extension RunningAppsMonitor.Snapshot {
    /// The running apps to show after the pinned `items`, in launch order: regular apps
    /// with a bundle that no pinned app matches by bundle identifier or path, other than
    /// the one with `ownBundleID` (OpenDock itself).
    func unpinnedApps(pinned items: [DockItem], excludingBundleID ownBundleID: String?) -> [RunningDockApp] {
        let pinnedIDs = Set(items.compactMap { $0.appItem?.bundleIdentifier })
        let pinnedPaths = Set(items.compactMap { $0.appItem?.url.normalizedPath })
        return regularApps.compactMap { app in
            guard let url = app.bundleURL else { return nil }
            if let bundleID = app.bundleIdentifier, bundleID == ownBundleID || pinnedIDs.contains(bundleID) {
                return nil
            }
            if pinnedPaths.contains(url.normalizedPath) { return nil }
            return RunningDockApp(
                id: RunningDockApp.ID(processIdentifier: app.processIdentifier, launchDate: app.launchDate),
                app: AppItem(url: url, bundleIdentifier: app.bundleIdentifier)
            )
        }
    }

    /// The recent apps to show after the running ones: the first `limit` of `recents` that
    /// aren't pinned among `items`, aren't running, and aren't OpenDock itself
    /// (`ownBundleID`). See `RecentApps.shown`.
    func recentApps(
        from recents: RecentApps, pinned items: [DockItem], excludingBundleID ownBundleID: String?, limit: Int
    ) -> [RecentDockApp] {
        recents.shown(
            pinned: items,
            runningBundleIDs: runningBundleIDs,
            runningBundlePaths: runningBundlePaths,
            excludingBundleID: ownBundleID,
            limit: limit
        )
    }
}

extension RunningAppsMonitor.AppDescriptor {
    /// Launch order: by launch date, then pid. Apps without a launch date (not launched
    /// through Launch Services) come last.
    static func launchedBefore(_ a: Self, _ b: Self) -> Bool {
        switch (a.launchDate, b.launchDate) {
        case let (x?, y?) where x != y: x < y
        case (_?, nil): true
        case (nil, _?): false
        default: a.processIdentifier < b.processIdentifier
        }
    }
}
