import DockCore
import Foundation
import SystemServices

/// Bouncing an app's icon while it launches, like Apple's Dock (see `LaunchBounce`).
extension DockController {
    /// Opens `app` the way clicking it in Apple's Dock does. Its icon bounces if that
    /// launches it, but not if the app was already running and is only brought forward.
    func open(_ app: AppItem) {
        let outcome = AppLauncher.open(app, running: running) { [weak self] result in
            self?.launchMonitor.launchCompleted(app, result: result)
        }
        guard outcome == .launching, store.settings.animateOpeningApps else { return }
        // Launch Services answers asynchronously, so the monitor hears of the launch first.
        guard shellState.launchBounces.start(app, at: .now) else { return }
        launchMonitor.launchRequested(app)
        scheduleLaunchBounceCleanup()
    }

    /// The app finished launching, failed to, or quit: its icon lands after this hop.
    func launchEnded(_ app: AppItem) {
        shellState.launchBounces.launchEnded(app, at: .now)
        scheduleLaunchBounceCleanup()
    }

    /// Clear each bounce once it's over, so nothing is redrawn for icons at rest. An app
    /// that never reports finishing its launch is given up on at the timeout.
    private func scheduleLaunchBounceCleanup() {
        launchBounceTask?.cancel()
        guard let next = shellState.launchBounces.nextEnd else {
            launchBounceTask = nil
            return
        }
        launchBounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)))
            guard let self, !Task.isCancelled else { return }
            for app in shellState.launchBounces.removeFinished(at: .now) {
                launchMonitor.stopWatching(app)
            }
            scheduleLaunchBounceCleanup()
        }
    }
}
