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
/// Observable because `dock` only exists after launch and the menu bar menu reads it.
@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = DockStore.load()
    let registry = WidgetRegistry()
    let running = RunningAppsMonitor()
    let launchAtLogin = LaunchAtLogin()
    let appleDock = AppleDockHider(backend: SystemAppleDockBackend())
    private(set) var dock: DockController?
    @ObservationIgnored private var appliedHideAppleDock: Bool?
    @ObservationIgnored private var signalSources: [any DispatchSourceSignal] = []

    @ObservationIgnored private lazy var settingsWindow = SettingsWindowController(
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
        syncAppleDock()
        terminateOnSignals()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
        appleDock.restore()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Brings the Settings window to the front, optionally switching to `tab`.
    func showSettings(_ tab: SettingsTab? = nil) {
        settingsWindow.show(tab)
    }

    /// Hides or restores Apple's Dock to match the setting, now and whenever it changes
    /// (including through Import and Reset). At launch this also restores Apple's Dock
    /// if a previous run was killed while hiding it.
    private func syncAppleDock() {
        let hide = withObservationTracking {
            store.settings.hideAppleDock
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor [weak self] in self?.syncAppleDock() }
        }
        guard hide != appliedHideAppleDock else { return }
        appliedHideAppleDock = hide
        appleDock.apply(hide: hide)
    }

    /// Quits through `applicationWillTerminate` on `kill`, Ctrl-C, or a closed terminal,
    /// so Apple's Dock gets restored. Only SIGKILL and crashes skip it; the next launch
    /// cleans up after those.
    private func terminateOnSignals() {
        signalSources = [SIGTERM, SIGINT, SIGHUP].map { signalNumber in
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
            source.resume()
            return source
        }
    }
}
