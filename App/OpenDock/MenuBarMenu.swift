import DockCore
import SwiftUI

/// Contents of the menu bar extra.
struct MenuBarMenu: View {
    @Environment(DockStore.self) private var store

    var body: some View {
        Text("OpenDock").font(.headline)
        Divider()
        Toggle("Auto-Hide Dock", isOn: Binding(
            get: { store.settings.autoHide },
            set: { value in store.updateSettings { $0.autoHide = value } }
        ))
        Divider()
        Button("Settings…") { AppDelegate.openSettings() }
            .keyboardShortcut(",")
        Button("Quit OpenDock") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
