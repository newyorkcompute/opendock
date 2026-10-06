import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// Reorder, remove, and add dock items; inspect the selected one.
struct DockItemsTab: View {
    @Environment(DockStore.self) private var store
    @Environment(WidgetRegistry.self) private var registry

    @State private var selection: DockItem.ID?

    private var selectedItem: DockItem? {
        selection.flatMap { store.profile.item(id: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.items) { item in
                        DockItemRow(item: item)
                            .tag(item.id)
                            .contextMenu { rowMenu(for: item) }
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
                }
                .listStyle(.inset)
                .alternatingRowBackgrounds()
                .onDeleteCommand(perform: removeSelection)

                Divider()
                listFooter
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.separator)
            )

            if let selectedItem {
                // Widget settings views seed @State from their instance; a fresh identity per
                // item keeps one widget's settings from leaking into another of the same type.
                DockItemInspector(item: selectedItem)
                    .id(selectedItem.id)
            } else {
                Text("Drag rows to reorder. Select an item to see its options.")
                    .settingsFootnote()
            }
        }
        .padding(20)
    }

    // MARK: - Footer

    private var listFooter: some View {
        HStack(spacing: 0) {
            Menu {
                addMenuItems
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 20)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add to Dock")

            Divider().frame(height: 16)

            Button(action: removeSelection) {
                Image(systemName: "minus")
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(selection == nil)
            .help("Remove from Dock")

            Spacer()

            Text(store.items.count == 1 ? "1 item" : "\(store.items.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.trailing, 8)
        }
        .padding(4)
        .background(.background)
    }

    @ViewBuilder
    private var addMenuItems: some View {
        Button("App…") { DockItemActions.promptForApps(into: store, after: selection) }
        Button("Folder…") { DockItemActions.promptForFolders(into: store, after: selection) }
        Menu("Spacer") {
            Button("Small") { selection = DockItemActions.addSpacer(.small, to: store, after: selection) }
            Button("Regular") { selection = DockItemActions.addSpacer(.regular, to: store, after: selection) }
        }
        Button("Divider") { selection = DockItemActions.addDivider(to: store, after: selection) }
        Menu("Widget") {
            ForEach(registry.descriptors) { descriptor in
                Button {
                    selection = DockItemActions.addWidget(descriptor.typeID, registry: registry, to: store, after: selection)
                } label: {
                    Label(descriptor.displayName, systemImage: descriptor.systemImage)
                }
            }
        }
    }

    @ViewBuilder
    private func rowMenu(for item: DockItem) -> some View {
        if let url = item.appItem?.url ?? item.folderItem?.url {
            Button("Show in Finder") { AppLauncher.revealInFinder(url) }
            Divider()
        }
        Button("Remove from Dock", role: .destructive) { remove(item.id) }
    }

    // MARK: - Mutations

    /// `onMove` reports the destination as an index into the array *before* the
    /// source is removed; `DockStore.move(id:to:)` expects the index *after* removal.
    private func move(from offsets: IndexSet, to destination: Int) {
        let items = store.items
        guard let source = offsets.first, items.indices.contains(source) else { return }
        store.move(id: items[source].id, to: destination > source ? destination - 1 : destination)
    }

    private func delete(at offsets: IndexSet) {
        let items = store.items
        offsets.filter(items.indices.contains).map { items[$0].id }.forEach(remove)
    }

    private func removeSelection() {
        guard let selection else { return }
        remove(selection)
    }

    private func remove(_ id: DockItem.ID) {
        if selection == id { selection = nil }
        store.remove(id: id)
    }
}
