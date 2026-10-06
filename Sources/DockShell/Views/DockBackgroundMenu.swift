import DockCore
import DockWidgetKit
import SwiftUI

/// Right-click menu on the dock's empty surface.
struct DockBackgroundMenu: View {
    let controller: DockController

    @Environment(DockStore.self) private var store
    @Environment(WidgetRegistry.self) private var registry

    var body: some View {
        Button("Add App…") { controller.promptForApp() }
        Button("Add Folder…") { controller.promptForFolder() }
        Menu("Add Spacer") {
            Button("Small") { store.append(.spacer(.small)) }
            Button("Regular") { store.append(.spacer(.regular)) }
        }
        Button("Add Divider") { store.append(.divider()) }
        Menu("Add Widget") {
            ForEach(registry.descriptors) { descriptor in
                Button {
                    if let widget = registry.widget(for: descriptor.typeID) {
                        store.append(DockItem(kind: .widget(widget.makeInstance())))
                    }
                } label: {
                    Label(descriptor.displayName, systemImage: descriptor.systemImage)
                }
            }
        }
        Divider()
        Toggle("Auto-Hide", isOn: Binding(
            get: { store.settings.autoHide },
            set: { value in store.updateSettings { $0.autoHide = value } }
        ))
        Divider()
        Button("Settings…") { controller.actions.openSettings() }
        Button("Quit OpenDock") { controller.actions.quit() }
    }
}
