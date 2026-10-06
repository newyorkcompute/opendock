import AppKit
import DockCore
import DockWidgetKit
import UniformTypeIdentifiers

/// Adding items to the dock from the menu bar and the Settings window. New items go right
/// after the item with ID `after` when there is one (the selected row in Settings), else at
/// the end.
enum DockItemActions {
    /// Shows an open panel for `.app` bundles and pins each chosen app (skipping duplicates).
    static func promptForApps(into store: DockStore, after anchor: DockItem.ID? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Add App"
        panel.message = "Choose applications to add to your dock."
        panel.prompt = "Add"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        var index = store.profile.index(after: anchor)
        for url in panel.urls where !store.profile.containsApp(at: url) {
            store.insert(.app(at: url), at: index)
            index += 1
        }
    }

    /// Shows an open panel for folders or files and pins each one (skipping duplicates).
    static func promptForFolders(into store: DockStore, after anchor: DockItem.ID? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Add Folder"
        panel.message = "Choose folders or files to keep in your dock."
        panel.prompt = "Add"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        var index = store.profile.index(after: anchor)
        for url in panel.urls where !store.profile.containsFolder(at: url) {
            store.insert(.folder(at: url), at: index)
            index += 1
        }
    }

    @discardableResult
    static func addSpacer(_ size: SpacerItem.Size, to store: DockStore, after anchor: DockItem.ID? = nil) -> DockItem.ID {
        insert(.spacer(size), into: store, after: anchor)
    }

    @discardableResult
    static func addDivider(to store: DockStore, after anchor: DockItem.ID? = nil) -> DockItem.ID {
        insert(.divider(), into: store, after: anchor)
    }

    /// Adds a new instance of the widget with its default settings.
    @discardableResult
    static func addWidget(_ typeID: String, registry: WidgetRegistry, to store: DockStore, after anchor: DockItem.ID? = nil) -> DockItem.ID? {
        guard let widget = registry.widget(for: typeID) else { return nil }
        return insert(DockItem(kind: .widget(widget.makeInstance())), into: store, after: anchor)
    }

    private static func insert(_ item: DockItem, into store: DockStore, after anchor: DockItem.ID?) -> DockItem.ID {
        store.insert(item, at: store.profile.index(after: anchor))
        return item.id
    }
}
