import AppKit
import DockCore
import SystemServices

/// The menu on app icons, which lists the app's windows like the Dock's, and
/// click-to-minimize. Windows are looked up only when the menu opens or the icon is clicked.
extension DockController {
    /// A click on an app's icon. With click-to-minimize on, clicking the frontmost app
    /// minimizes its windows, or restores them if they're all minimized. Otherwise, and
    /// whenever that can't be done, the app opens as usual.
    func appClicked(_ app: AppItem) {
        if store.settings.clickToMinimize,
            let runningApp = running.runningApplication(bundleIdentifier: app.bundleIdentifier, bundleURL: app.url),
            runningApp.isActive,
            windows.toggleMinimized(ofProcess: runningApp.processIdentifier) != nil
        {
            return
        }
        open(app)
    }

    /// Opens the app's menu at the pointer. `processIdentifier` picks the instance whose
    /// windows to list; without it, it's the first running instance of `app`.
    func showAppMenu(for app: AppItem, pinnedID: DockItem.ID?, processIdentifier: pid_t? = nil) {
        let location = NSEvent.mouseLocation
        // Start the menu's tracking loop after the event that asked for it has finished.
        Task { [weak self] in
            guard let self else { return }
            let menu = appMenu(for: app, pinnedID: pinnedID, processIdentifier: processIdentifier)
            _ = menu.popUp(positioning: nil, at: location, in: nil)
        }
    }

    func appMenu(for app: AppItem, pinnedID: DockItem.ID?, processIdentifier: pid_t?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let title = NSMenuItem(title: app.displayName, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let runningApp = running.runningApplication(bundleIdentifier: app.bundleIdentifier, bundleURL: app.url)
        if let processIdentifier = processIdentifier ?? runningApp?.processIdentifier {
            addWindowItems(to: menu, app: app, processIdentifier: processIdentifier)
        }
        if runningApp != nil {
            menu.addItem(actionMenuItem("Hide") { [running] in AppLauncher.hide(app, running: running) })
            menu.addItem(actionMenuItem("Quit") { [running] in AppLauncher.quit(app, running: running) })
        } else {
            menu.addItem(actionMenuItem("Open") { [weak self] in self?.open(app) })
        }
        menu.addItem(actionMenuItem("New Window") { AppLauncher.openNewInstance(app) })
        menu.addItem(.separator())
        menu.addItem(actionMenuItem("Show in Finder") { AppLauncher.revealInFinder(app.url) })
        menu.addItem(.separator())
        if let pinnedID {
            menu.addItem(actionMenuItem("Remove from Dock") { [store] in store.remove(id: pinnedID) })
        } else {
            menu.addItem(actionMenuItem("Keep in Dock") { [store] in store.addApp(at: app.url) })
        }
        return menu
    }

    /// The app's windows, each brought to the front when chosen. The main window is checked
    /// and minimized ones get a diamond, as in the Dock and the Window menu. Without
    /// Accessibility access there's an item that asks for it instead.
    private func addWindowItems(to menu: NSMenu, app: AppItem, processIdentifier: pid_t) {
        guard windows.refreshTrust() else {
            let item = actionMenuItem("Allow Access to Windows…") { [windows] in windows.requestAccess() }
            item.toolTip = "OpenDock needs Accessibility access to list and switch between an app’s windows."
            menu.addItem(item)
            menu.addItem(.separator())
            return
        }
        let appWindows = windows.menuWindows(ofProcess: processIdentifier)
        guard !appWindows.isEmpty else { return }
        for window in appWindows {
            let item = actionMenuItem(window.title.isEmpty ? app.displayName : window.title) { [windows] in
                windows.bringToFront(window, ofProcess: processIdentifier)
            }
            if window.isMinimized {
                item.state = .mixed
                item.mixedStateImage = Self.minimizedWindowImage
            } else if window.isMain {
                item.state = .on
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
    }

    private static let minimizedWindowImage = NSImage(
        systemSymbolName: "diamond.fill", accessibilityDescription: "Minimized"
    )?
    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 7, weight: .regular))

    /// The app under `point` (layout coordinates), pinned or running, for its menu.
    func appMenuTarget(at point: CGPoint) -> (app: AppItem, pinnedID: DockItem.ID?, processIdentifier: pid_t?)? {
        guard let hit = shellState.geometry.itemFrames.first(where: { $0.frame.contains(point) })?.id else {
            return nil
        }
        switch hit {
        case let .pinned(id):
            guard let app = store.profile.item(id: id)?.appItem else { return nil }
            return (app, id, nil)
        case let .running(id):
            let extras = running.snapshot.unpinnedApps(
                pinned: store.items, excludingBundleID: Bundle.main.bundleIdentifier)
            guard let extra = extras.first(where: { $0.id == id }) else { return nil }
            return (extra.app, nil, id.processIdentifier)
        }
    }
}
