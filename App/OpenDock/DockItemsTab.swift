import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// Reorder, remove, and add dock items; inspect the selected one.
struct DockItemsTab: View {
    @Environment(DockStore.self) private var store
    @Environment(WidgetRegistry.self) private var registry
    @Environment(ProfileSwitcher.self) private var profiles
    @Environment(AccessibilityPermission.self) private var accessibility
    @Environment(ScreenRecordingPermission.self) private var screenRecording

    @State private var selection: DockItem.ID?

    private var selectedItem: DockItem? {
        selection.flatMap { store.profile.item(id: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.profiles.count > 1 {
                Picker(
                    "Profile",
                    selection: Binding(
                        get: { store.activeProfileID },
                        set: { profiles.select($0) }
                    )
                ) {
                    ForEach(store.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .fixedSize()
                .help("The profile whose items you’re editing, which is also the one the dock shows")
            }

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

            Toggle(
                "Show Trash",
                isOn: Binding(
                    get: { store.showsTrash },
                    set: { store.setShowsTrash($0) }
                )
            )
            .help(
                "Keep the Trash at the end of the dock, after running apps, recent apps, and minimized windows, like Apple's Dock."
            )

            minimizedWindowsSettings

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
        .onChange(of: store.activeProfileID) { selection = nil }
    }

    /// Applies to every profile: it's a dock setting, edited here because this is where the
    /// row's sections are chosen.
    @ViewBuilder
    private var minimizedWindowsSettings: some View {
        Toggle(
            "Show minimized windows",
            isOn: Binding(
                get: { store.settings.showMinimizedWindows },
                set: { enabled in
                    store.updateSettings { $0.showMinimizedWindows = enabled }
                    if enabled { accessibility.request() }
                }
            )
        )
        .help(
            "Show each minimized window after the running and recent apps, before the Trash. Clicking one restores it. Applies to every profile."
        )

        if store.settings.showMinimizedWindows {
            if !accessibility.isGranted {
                LabeledContent("Accessibility access") {
                    Button("Allow…") { accessibility.request() }
                }
                Text(
                    "Minimized windows are read through Accessibility. OpenDock doesn’t look for them until access is allowed, and it doesn’t ask at launch."
                )
                .settingsFootnote()
            }

            LabeledContent("Window thumbnails") {
                if screenRecording.isGranted {
                    Text("Allowed").foregroundStyle(.secondary)
                } else {
                    Button("Allow Screen Recording…") { screenRecording.request() }
                }
            }
            Text(
                "A thumbnail needs Screen Recording permission, which OpenDock never asks for on its own. Without it, a minimized window shows its app icon with a small window glyph. Allowing it may need a restart of OpenDock. Nothing is recorded or saved."
            )
            .settingsFootnote()
        }
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
                    selection = DockItemActions.addWidget(
                        descriptor.typeID, registry: registry, to: store, after: selection)
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
