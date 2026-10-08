import AppKit
import DockCore

/// Which of the apps the dock launched are still launching. Plain bookkeeping, fed by
/// `AppLaunchMonitor`, so the matching can be unit tested.
///
/// A launch is matched to the process Launch Services started for it once that's known,
/// and until then to any process of the same app (by bundle identifier or path): the
/// system may report the app finished launching before the dock hears its process ID.
public struct AppLaunchTracker: Sendable {
    struct Launch: Sendable {
        var app: AppItem
        var processIdentifier: pid_t?
    }

    private(set) var launches: [Launch] = []

    public init() {}

    public var isEmpty: Bool { launches.isEmpty }

    /// The launched processes to check on: the ones whose process ID is known.
    public var processIdentifiers: [pid_t] { launches.compactMap(\.processIdentifier) }

    /// Start watching `app`'s launch. Watching it already is a no-op.
    public mutating func launchRequested(_ app: AppItem) {
        guard !launches.contains(where: { $0.app.isSameApp(as: app) }) else { return }
        launches.append(Launch(app: app))
    }

    /// Launch Services started `app` as `processIdentifier`. Ignored unless the launch is
    /// still being watched.
    public mutating func launched(_ app: AppItem, processIdentifier: pid_t) {
        for index in launches.indices where launches[index].app.isSameApp(as: app) {
            launches[index].processIdentifier = processIdentifier
        }
    }

    /// A process finished launching or quit. Returns the launches that ended with it.
    public mutating func processEnded(
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        bundleURL: URL?
    ) -> [AppItem] {
        let process = bundleURL.map { AppItem(url: $0, bundleIdentifier: bundleIdentifier) }
        return removeLaunches { launch in
            if let pid = launch.processIdentifier { return pid == processIdentifier }
            if let bundleIdentifier, bundleIdentifier == launch.app.bundleIdentifier { return true }
            return process.map(launch.app.isSameApp(as:)) ?? false
        }
    }

    /// Stop watching `app`'s launch: it failed, or the dock stopped waiting for it.
    /// Returns whether it was being watched.
    @discardableResult
    public mutating func stopWatching(_ app: AppItem) -> Bool {
        !removeLaunches { $0.app.isSameApp(as: app) }.isEmpty
    }

    private mutating func removeLaunches(where matches: (Launch) -> Bool) -> [AppItem] {
        let ended = launches.filter(matches).map(\.app)
        launches.removeAll(where: matches)
        return ended
    }
}

/// Tells when apps the dock launched have finished launching, failed to, or quit before
/// they did, so their icons can stop bouncing.
///
/// Regular apps announce it with `didLaunchApplicationNotification`. Apps that don't
/// (agents with `LSUIElement`) are found by checking `isFinishedLaunching` on the launched
/// process a few times a second. Nothing is observed or polled while no launch is watched.
@MainActor
public final class AppLaunchMonitor {
    /// Called once for each watched launch, when it ends.
    public var onLaunchEnded: ((AppItem) -> Void)?

    private var tracker = AppLaunchTracker()
    private var observers: [any NSObjectProtocol] = []
    private var pollTask: Task<Void, Never>?

    static let pollInterval = Duration.milliseconds(200)

    public init() {}

    isolated deinit {
        pollTask?.cancel()
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
    }

    /// The dock asked Launch Services to launch `app`.
    public func launchRequested(_ app: AppItem) {
        tracker.launchRequested(app)
        update()
    }

    /// Launch Services' answer for a launch of `app`.
    public func launchCompleted(_ app: AppItem, result: AppLaunchResult) {
        switch result {
        case let .launched(processIdentifier):
            tracker.launched(app, processIdentifier: processIdentifier)
            checkProcesses()
        case .failed:
            if tracker.stopWatching(app) { onLaunchEnded?(app) }
        }
        update()
    }

    /// Stop waiting for `app`, without reporting its launch as ended.
    public func stopWatching(_ app: AppItem) {
        tracker.stopWatching(app)
        update()
    }

    private func processEnded(processIdentifier: pid_t, bundleIdentifier: String?, bundleURL: URL?) {
        let ended = tracker.processEnded(
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier,
            bundleURL: bundleURL
        )
        ended.forEach { onLaunchEnded?($0) }
        update()
    }

    /// A process of a watched app announced its launch. Ends the launch if the process says
    /// it's done; otherwise it's the one to poll.
    private func processLaunched(_ process: LaunchedProcess) {
        if process.isFinishedLaunching {
            processEnded(
                processIdentifier: process.pid, bundleIdentifier: process.bundleIdentifier, bundleURL: process.bundleURL
            )
        } else if let url = process.bundleURL {
            tracker.launched(
                AppItem(url: url, bundleIdentifier: process.bundleIdentifier), processIdentifier: process.pid)
            update()
        }
    }

    private func checkProcesses() {
        for pid in tracker.processIdentifiers {
            let app = NSRunningApplication(processIdentifier: pid)
            if let app, !app.isFinishedLaunching, !app.isTerminated { continue }
            processEnded(processIdentifier: pid, bundleIdentifier: app?.bundleIdentifier, bundleURL: app?.bundleURL)
        }
    }

    /// Observe and poll only while there's something to watch.
    private func update() {
        if tracker.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            observers.forEach(center.removeObserver)
            observers = []
        } else if observers.isEmpty {
            observe()
        }

        if tracker.processIdentifiers.isEmpty {
            pollTask?.cancel()
            pollTask = nil
        } else if pollTask == nil {
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.pollInterval)
                    guard !Task.isCancelled, let self else { return }
                    self.checkProcesses()
                }
            }
        }
    }

    private func observe() {
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) {
                [weak self] note in
                guard let process = LaunchedProcess(note) else { return }
                MainActor.assumeIsolated { self?.processLaunched(process) }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) {
                [weak self] note in
                guard let process = LaunchedProcess(note) else { return }
                MainActor.assumeIsolated {
                    self?.processEnded(
                        processIdentifier: process.pid, bundleIdentifier: process.bundleIdentifier,
                        bundleURL: process.bundleURL)
                }
            },
        ]
    }
}

/// The parts of a workspace notification's app that are needed, read where it's posted.
private struct LaunchedProcess: Sendable {
    let pid: pid_t
    let bundleIdentifier: String?
    let bundleURL: URL?
    let isFinishedLaunching: Bool

    init?(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return nil }
        pid = app.processIdentifier
        bundleIdentifier = app.bundleIdentifier
        bundleURL = app.bundleURL
        isFinishedLaunching = app.isFinishedLaunching
    }
}
