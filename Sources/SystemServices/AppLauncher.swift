import AppKit
import DockCore

/// Launching, activating, quitting, and revealing apps and files.
@MainActor
public enum AppLauncher {
    /// Launches the app, or brings it to the front if it is already running.
    public static func open(_ app: AppItem, running: RunningAppsMonitor) {
        if let runningApp = running.runningApplication(bundleIdentifier: app.bundleIdentifier, bundleURL: app.url) {
            if runningApp.isHidden {
                runningApp.unhide()
            }
            runningApp.activate()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, error in
            if let error {
                NSLog("OpenDock: failed to open \(app.url.path): \(error.localizedDescription)")
            }
        }
    }

    /// Opens a new instance even if one is running (⌘-click behaviour).
    public static func openNewInstance(_ app: AppItem) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration)
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

    /// Opens a folder or file with its default handler (Finder for folders).
    public static func open(_ folder: FolderItem) {
        NSWorkspace.shared.open(folder.url)
    }

    public static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public static func open(url: URL) {
        NSWorkspace.shared.open(url)
    }
}
