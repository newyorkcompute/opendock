import DockCore
import Foundation
import SystemServices

/// The sections after the pinned items: running apps that aren't pinned, then recently
/// used apps that are neither pinned nor running. Each is empty while its setting is off.
extension DockController {
    var runningSection: [RunningDockApp] {
        guard store.settings.showRunningApps else { return [] }
        return running.snapshot.unpinnedApps(pinned: store.items, excludingBundleID: Bundle.main.bundleIdentifier)
    }

    var recentSection: [RecentDockApp] {
        guard store.settings.showRecentApps else { return [] }
        return running.snapshot.recentApps(
            from: store.recentApps,
            pinned: store.items,
            excludingBundleID: Bundle.main.bundleIdentifier,
            limit: store.settings.recentAppsCount
        )
    }

    // MARK: - Recent apps

    /// Called by the root view's `onChange(of: settings.showRecentApps)`. Apps are only
    /// tracked while the section is on, so nothing about app use is written down otherwise.
    func recentAppsSettingChanged(_ enabled: Bool) {
        if enabled {
            activationMonitor.onActivate = { [weak self] app in self?.appActivated(app) }
        } else {
            activationMonitor.onActivate = nil
        }
    }

    /// The user switched to `app`: it's now the most recent app. OpenDock itself doesn't
    /// count (it's only ever a regular app when run unbundled).
    private func appActivated(_ app: AppItem) {
        if let own = Bundle.main.bundleIdentifier, app.bundleIdentifier == own { return }
        store.recordRecentApp(app)
    }
}
