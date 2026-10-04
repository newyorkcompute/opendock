import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// Options for the item selected in the Dock Items list.
struct DockItemInspector: View {
    let item: DockItem

    @Environment(DockStore.self) private var store
    @Environment(WidgetRegistry.self) private var registry

    var body: some View {
        GroupBox {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case let .app(app):
            fileDetails(url: app.url, extra: app.bundleIdentifier)
        case let .folder(folder):
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: folderNameBinding(folder), prompt: Text(folder.url.lastPathComponent))
                fileDetails(url: folder.url, extra: nil)
            }
        case let .spacer(spacer):
            Picker("Spacer size", selection: spacerSizeBinding(spacer)) {
                Text("Small").tag(SpacerItem.Size.small)
                Text("Regular").tag(SpacerItem.Size.regular)
            }
            .pickerStyle(.segmented)
            .fixedSize()
        case let .widget(instance):
            widgetSettings(instance)
        }
    }

    private func fileDetails(url: URL, extra: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(url.path)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                if let extra {
                    Text(extra)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .font(.caption)
            Spacer()
            Button("Show in Finder") { AppLauncher.revealInFinder(url) }
                .disabled(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @ViewBuilder
    private func widgetSettings(_ instance: WidgetInstance) -> some View {
        if let widget = registry.widget(for: instance) {
            VStack(alignment: .leading, spacing: 8) {
                Label(widget.displayName, systemImage: widget.systemImage)
                    .font(.headline)
                if let settingsView = widget.makeSettingsView(instance: instance) {
                    settingsView
                        .environment(\.widgetUpdateSettings, updater)
                } else {
                    Text("This widget has no options.")
                        .settingsFootnote()
                }
            }
        } else {
            Text("“\(instance.typeID)” isn’t available in this version of OpenDock.")
                .settingsFootnote()
        }
    }

    // MARK: - Bindings

    private var updater: WidgetSettingsUpdater {
        WidgetSettingsUpdater(id: item.id) { [store, item] updated in
            var copy = item
            copy.kind = .widget(updated)
            store.updateItem(copy)
        }
    }

    private func folderNameBinding(_ folder: FolderItem) -> Binding<String> {
        Binding(
            get: { folder.customName ?? "" },
            set: { value in
                var updated = folder
                updated.customName = value.isEmpty ? nil : value
                var copy = item
                copy.kind = .folder(updated)
                store.updateItem(copy)
            }
        )
    }

    private func spacerSizeBinding(_ spacer: SpacerItem) -> Binding<SpacerItem.Size> {
        Binding(
            get: { spacer.size },
            set: { size in
                var copy = item
                copy.kind = .spacer(SpacerItem(size: size))
                store.updateItem(copy)
            }
        )
    }
}
