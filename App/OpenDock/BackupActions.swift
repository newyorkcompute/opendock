import AppKit
import DockCore
import UniformTypeIdentifiers

/// Exporting and importing the whole dock document as JSON.
enum BackupActions {
    static let defaultFileName = "OpenDock Layout.json"

    static func exportLayout(from store: DockStore) {
        let panel = NSSavePanel()
        panel.title = "Export Layout"
        panel.message = "Save your profiles, dock items, widgets, and settings to a file."
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = defaultFileName
        panel.canCreateDirectories = true
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData().write(to: url, options: .atomic)
        } catch {
            showError(title: "Couldn’t export layout", error: error)
        }
    }

    /// Replaces the current document with one chosen by the user.
    static func importLayout(into store: DockStore) {
        let panel = NSOpenPanel()
        panel.title = "Import Layout"
        panel.message = "Importing replaces all your current profiles and settings."
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importData(Data(contentsOf: url))
        } catch {
            showError(title: "Couldn’t import “\(url.lastPathComponent)”", error: error)
        }
    }

    private static func showError(title: String, error: any Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}
