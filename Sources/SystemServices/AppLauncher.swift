import AppKit
import DockCore

/// The parts of a running app that `AppLauncher` drives. `NSRunningApplication` in production.
@MainActor
public protocol RunningAppHandle: AnyObject {
    var bundleURL: URL? { get }
    var isHidden: Bool { get }
    @discardableResult func unhide() -> Bool
    @discardableResult func activate(options: NSApplication.ActivationOptions) -> Bool
}

extension NSRunningApplication: RunningAppHandle {}

/// Finds the running instance of a dock item. `RunningAppsMonitor` in production.
@MainActor
public protocol RunningAppLookup {
    func runningApp(bundleIdentifier: String?, bundleURL: URL) -> (any RunningAppHandle)?
}

extension RunningAppsMonitor: RunningAppLookup {
    public func runningApp(bundleIdentifier: String?, bundleURL: URL) -> (any RunningAppHandle)? {
        runningApplication(bundleIdentifier: bundleIdentifier, bundleURL: bundleURL)
    }
}

/// What Launch Services reported back after opening an app.
public enum AppLaunchResult: Hashable, Sendable {
    case launched(processIdentifier: pid_t)
    case failed
}

/// What opening an app from the dock did.
public enum AppOpenOutcome: Hashable, Sendable {
    /// It wasn't running, and Launch Services is launching it.
    case launching
    /// It was already running, and was brought forward.
    case activated
}

/// The `NSWorkspace` calls `AppLauncher` makes.
@MainActor
public protocol AppWorkspace {
    /// Calls `completion` on the main actor once Launch Services has opened the app, or
    /// failed to.
    func openApplication(
        at url: URL,
        configuration: NSWorkspace.OpenConfiguration,
        completion: @escaping @MainActor @Sendable (AppLaunchResult) -> Void
    )
    func open(_ url: URL, configuration: NSWorkspace.OpenConfiguration)
    func activateFileViewerSelecting(_ urls: [URL])
}

extension AppWorkspace {
    func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) {
        openApplication(at: url, configuration: configuration) { _ in }
    }
}

public struct SystemAppWorkspace: AppWorkspace {
    public init() {}

    public func openApplication(
        at url: URL,
        configuration: NSWorkspace.OpenConfiguration,
        completion: @escaping @MainActor @Sendable (AppLaunchResult) -> Void
    ) {
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            if let error {
                NSLog("OpenDock: failed to open \(url.path): \(error.localizedDescription)")
            }
            let result: AppLaunchResult = if let app, error == nil {
                .launched(processIdentifier: app.processIdentifier)
            } else {
                .failed
            }
            Task { @MainActor in completion(result) }
        }
    }

    public func open(_ url: URL, configuration: NSWorkspace.OpenConfiguration) {
        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            if let error {
                NSLog("OpenDock: failed to open \(url.path): \(error.localizedDescription)")
            }
        }
    }

    public func activateFileViewerSelecting(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

/// Launching, activating, quitting, and revealing apps and files.
@MainActor
public enum AppLauncher {
    /// Does what clicking the app in Apple's Dock does: launches it if it isn't running;
    /// otherwise unhides it, brings all its windows forward, and sends it the reopen event
    /// so an app with no visible windows shows one (a new window, a deminiaturized one,
    /// or for Finder a new browser window).
    ///
    /// `launchCompleted` is called with Launch Services' result when this launches the app,
    /// and never when the app was already running.
    @discardableResult
    public static func open(
        _ app: AppItem,
        running: some RunningAppLookup,
        workspace: any AppWorkspace = SystemAppWorkspace(),
        launchCompleted: @escaping @MainActor @Sendable (AppLaunchResult) -> Void = { _ in }
    ) -> AppOpenOutcome {
        guard let runningApp = running.runningApp(bundleIdentifier: app.bundleIdentifier, bundleURL: app.url) else {
            workspace.openApplication(at: app.url, configuration: activatingConfiguration(), completion: launchCompleted)
            return .launching
        }
        if runningApp.isHidden {
            runningApp.unhide()
        }
        // From a background app (the dock never activates) macOS 14+ may decline this
        // request; the open below activates through LaunchServices either way.
        runningApp.activate(options: .activateAllWindows)
        // `activate` alone never sends kAEReopenApplication. LaunchServices does when an
        // already-running app is opened, which is also how Finder and Apple's Dock do it.
        workspace.openApplication(at: runningApp.bundleURL ?? app.url, configuration: activatingConfiguration())
        return .activated
    }

    /// Opens a new instance even if one is running (⌘-click behaviour).
    public static func openNewInstance(_ app: AppItem, workspace: any AppWorkspace = SystemAppWorkspace()) {
        workspace.openApplication(at: app.url, configuration: activatingConfiguration(newInstance: true))
    }

    public static func quit(_ app: AppItem, running: RunningAppsMonitor, force: Bool = false) {
        guard let runningApp = running.runningApplication(bundleIdentifier: app.bundleIdentifier, bundleURL: app.url) else { return }
        if force {
            runningApp.forceTerminate()
        } else {
            runningApp.terminate()
        }
    }

    public static func hide(_ app: AppItem, running: RunningAppsMonitor) {
        running.runningApplication(bundleIdentifier: app.bundleIdentifier, bundleURL: app.url)?.hide()
    }

    /// Opens a folder or file with its default handler (Finder for folders) and brings it forward.
    public static func open(_ folder: FolderItem, workspace: any AppWorkspace = SystemAppWorkspace()) {
        workspace.open(folder.url, configuration: activatingConfiguration())
    }

    public static func revealInFinder(_ url: URL, workspace: any AppWorkspace = SystemAppWorkspace()) {
        workspace.activateFileViewerSelecting([url])
    }

    public static func open(url: URL, workspace: any AppWorkspace = SystemAppWorkspace()) {
        workspace.open(url, configuration: activatingConfiguration())
    }

    private static func activatingConfiguration(newInstance: Bool = false) -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = newInstance
        return configuration
    }
}
