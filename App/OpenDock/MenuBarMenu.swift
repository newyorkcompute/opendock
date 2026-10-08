import DockCore
import DockWidgetKit
import SwiftUI

/// Contents of the menu bar extra (menu style).
struct MenuBarMenu: View {
    let app: AppDelegate

    @Environment(DockStore.self) private var store
    @Environment(WidgetRegistry.self) private var registry
    @Environment(ProfileSwitcher.self) private var profiles

    var body: some View {
        Text("OpenDock")

        Divider()

        if store.profiles.count > 1 {
            ForEach(Array(store.profiles.enumerated()), id: \.element.id) { index, profile in
                Toggle(
                    profile.name,
                    isOn: Binding(
                        get: { profile.id == store.activeProfileID },
                        set: { isOn in if isOn { profiles.select(profile.id) } }
                    )
                )
                .keyboardShortcut(index < 9 ? KeyboardShortcut(KeyEquivalent(Character("\(index + 1)"))) : nil)
            }
        }
        Button("Profiles…") { app.showSettings(.profiles) }

        Divider()

        if store.settings.autoHide, let dock = app.dock {
            Button(dock.isVisible ? "Hide Dock" : "Show Dock") {
                if dock.isVisible { dock.hide() } else { dock.revealAndHold() }
            }
        }
        Toggle(
            "Auto-Hide Dock",
            isOn: Binding(
                get: { store.settings.autoHide },
                set: { value in store.updateSettings { $0.autoHide = value } }
            ))

        Divider()

        Menu("Add to Dock") {
            Button("App…") { DockItemActions.promptForApps(into: store) }
            Button("Folder…") { DockItemActions.promptForFolders(into: store) }
            Menu("Spacer") {
                Button("Small") { DockItemActions.addSpacer(.small, to: store) }
                Button("Regular") { DockItemActions.addSpacer(.regular, to: store) }
            }
            Button("Divider") { DockItemActions.addDivider(to: store) }
            if !registry.descriptors.isEmpty {
                Divider()
                ForEach(registry.descriptors) { descriptor in
                    Button {
                        DockItemActions.addWidget(descriptor.typeID, registry: registry, to: store)
                    } label: {
                        Label(descriptor.displayName, systemImage: descriptor.systemImage)
                    }
                }
            }
        }

        Divider()

        Button("Export Layout…") { BackupActions.exportLayout(from: store) }
        Button("Import Layout…") { BackupActions.importLayout(into: store) }

        Divider()

        Button("Settings…") { app.showSettings() }
            .keyboardShortcut(",")
        Button("About OpenDock") { app.showSettings(.about) }

        Divider()

        Button("Quit OpenDock") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
