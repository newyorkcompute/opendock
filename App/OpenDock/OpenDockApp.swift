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
            MenuBarMenu()
                .environment(appDelegate.store)
                .environment(appDelegate.registry)
        }

        Settings {
            SettingsView()
                .environment(appDelegate.store)
                .environment(appDelegate.registry)
        }
    }
}

/// Owns the long-lived objects. Created once by SwiftUI at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = DockStore.load()
    let registry = WidgetRegistry()
    let running = RunningAppsMonitor()
    private(set) var dock: DockController!

    override init() {
        super.init()
        registry.register([ClockWidget.self, BatteryWidget.self, CalendarWidget.self])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        dock = DockController(
            store: store,
            registry: registry,
            running: running,
            actions: DockActions(
                openSettings: { AppDelegate.openSettings() },
                quit: { NSApp.terminate(nil) }
            )
        )
        dock.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    static func openSettings() {
        NSApp.activate()
        // SwiftUI's Settings scene responds to this selector on macOS 14+.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
