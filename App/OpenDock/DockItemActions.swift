import AppKit
import DockCore
import DockWidgetKit
import UniformTypeIdentifiers

/// Adding items to the dock from the menu bar and the Settings window.
enum DockItemActions {
    /// Shows an open panel for `.app` bundles and pins each chosen app (skipping duplicates).
    static func promptForApps(into store: DockStore) {
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
        panel.urls.forEach { store.addApp(at: $0) }
    }

    /// Shows an open panel for folders or files and pins each one (skipping duplicates).
    static func promptForFolders(into store: DockStore) {
        let panel = NSOpenPanel()
        panel.title = "Add Folder"
        panel.message = "Choose folders or files to keep in your dock."
        panel.prompt = "Add"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { store.addFolder(at: $0) }
    }

    @discardableResult
    static func addSpacer(_ size: SpacerItem.Size, to store: DockStore) -> DockItem.ID {
        let item = DockItem.spacer(size)
        store.append(item)
        return item.id
    }

    /// Appends a new instance of the widget with its default settings.
    @discardableResult
    static func addWidget(_ typeID: String, registry: WidgetRegistry, to store: DockStore) -> DockItem.ID? {
        guard let widget = registry.widget(for: typeID) else { return nil }
        let item = DockItem(kind: .widget(widget.makeInstance()))
        store.append(item)
        return item.id
    }
}
