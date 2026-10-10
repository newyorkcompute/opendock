import AppKit
import DockCore
import SystemServices

/// Minimized windows at the end of the dock: restoring and closing them, and the menu
/// a right-click opens. The list itself lives on `minimizedWindows`.
extension DockController {
    /// Clicking a minimized window, and Return while the keyboard has it selected.
    func restoreMinimizedWindow(_ window: MinimizedDockWindow) {
        minimizedWindows.restore(window)
    }

    /// The minimized window under `point` (layout coordinates), for its menu.
    func minimizedWindow(at point: CGPoint) -> MinimizedDockWindow? {
        guard let hit = shellState.geometry.itemFrames.first(where: { $0.frame.contains(point) })?.id,
            case let .minimized(id) = hit
        else { return nil }
        return minimizedWindows.windows.first { $0.id == id }
    }

    /// Restore and Close, like the Dock's menu on a minimized window. `location` is in
    /// screen coordinates; the pointer's location is used when the click didn't say.
    func showMinimizedWindowMenu(for window: MinimizedDockWindow, at location: NSPoint? = nil) {
        let location = location ?? NSEvent.mouseLocation
        let monitor = minimizedWindows
        // Start the menu's tracking loop after the event that asked for it has finished.
        Task { @MainActor in
            let menu = NSMenu()
            menu.autoenablesItems = false
            let title = NSMenuItem(title: window.label, action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            menu.addItem(.separator())
            menu.addItem(actionMenuItem("Restore") { monitor.restore(window) })
            menu.addItem(actionMenuItem("Close") { monitor.close(window) })
            _ = menu.popUp(positioning: nil, at: location, in: nil)
        }
    }

    /// Called when the app becomes active, so a permission changed in System Settings
    /// starts or stops the minimized windows without a timer.
    func minimizedWindowsMayHaveChanged() {
        minimizedWindows.noteAppBecameActive()
    }

    /// Installed from `start` and removed from `stop`. Reading the two permissions does
    /// nothing until one of them has changed; the monitor still won't query windows
    /// without Accessibility access.
    func observeActivationForMinimizedWindows() {
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.minimizedWindowsMayHaveChanged() }
        }
    }
}
