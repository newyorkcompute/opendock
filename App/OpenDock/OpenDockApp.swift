import BatteryWidget
import CalendarWidget
import ClockWidget
import DockCore
import DockShell
import DockWidgetKit
import SwiftUI
import SystemServices

@main
struct OpenDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("OpenDock", systemImage: "dock.rectangle") {
            MenuBarMenu(app: appDelegate)
                .environment(appDelegate.store)
                .environment(appDelegate.registry)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Owns the long-lived objects. Created once by SwiftUI at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = DockStore.load()
    let registry = WidgetRegistry()
    let running = RunningAppsMonitor()
    let launchAtLogin = LaunchAtLogin()
    private(set) var dock: DockController?

    private lazy var settingsWindow = SettingsWindowController(
        store: store,
        registry: registry,
        launchAtLogin: launchAtLogin
    )

    override init() {
        super.init()
        registry.register([ClockWidget.self, BatteryWidget.self, CalendarWidget.self])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let dock = DockController(
            store: store,
            registry: registry,
            running: running,
            actions: DockActions(
                openSettings: { [weak self] in self?.showSettings() },
                quit: { NSApp.terminate(nil) }
            )
        )
        self.dock = dock
        dock.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Brings the Settings window to the front, optionally switching to `tab`.
    func showSettings(_ tab: SettingsTab? = nil) {
        settingsWindow.show(tab)
    }
}
