import DockCore
import DockWidgetKit
import SwiftUI

/// Right-click menu on the dock's empty surface, also shown in a spacer's menu. Items it
/// adds go where it was opened: after `anchor` (the spacer), or at the right-click.
struct DockBackgroundMenu: View {
    let controller: DockController
    var anchor: DockItem.ID?

    @Environment(DockStore.self) private var store
    @Environment(WidgetRegistry.self) private var registry

    var body: some View {
        Button("Add App…") { controller.promptForApp(at: insertionIndex) }
        Button("Add Folder…") { controller.promptForFolder(at: insertionIndex) }
        Menu("Add Spacer") {
            Button("Small") { add(.spacer(.small)) }
            Button("Regular") { add(.spacer(.regular)) }
        }
        Button("Add Divider") { add(.divider()) }
        Menu("Add Widget") {
            ForEach(registry.descriptors) { descriptor in
                Button {
                    if let widget = registry.widget(for: descriptor.typeID) {
                        add(DockItem(kind: .widget(widget.makeInstance())))
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

    private var insertionIndex: Int {
        controller.menuInsertionIndex(after: anchor)
    }

    private func add(_ item: DockItem) {
        store.insert(item, at: insertionIndex)
    }
}
