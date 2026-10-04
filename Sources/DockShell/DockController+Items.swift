import AppKit
import DockCore
import UniformTypeIdentifiers

/// Adding items from drops and open panels, and reordering.
extension DockController {
    /// Files dropped from Finder: `.app` bundles become apps, everything else a folder/file item.
    @discardableResult
    func handleDroppedURLs(_ urls: [URL]) -> Bool {
        var changed = false
        for url in urls where url.isFileURL {
            if url.pathExtension == "app" {
                changed = store.addApp(at: url) || changed
            } else {
                changed = store.addFolder(at: url) || changed
            }
        }
        return changed
    }

    /// Reorder payloads are item UUID strings (see `DockItemView.draggable`).
    @discardableResult
    func handleReorderDrop(_ payloads: [String], onto targetID: DockItem.ID) -> Bool {
        var moved = false
        for payload in payloads {
            guard let id = UUID(uuidString: payload), id != targetID,
                  store.profile.item(id: id) != nil
            else { continue }
            store.move(id: id, before: targetID)
            moved = true
        }
        shellState.draggingItemID = nil
        return moved
    }

    func promptForApp() {
        presentingSystemPanel {
            let panel = NSOpenPanel()
            panel.title = "Add App"
            panel.message = "Choose an application to add to your dock."
            panel.allowedContentTypes = [.application]
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            if panel.runModal() == .OK {
                panel.urls.forEach { store.addApp(at: $0) }
            }
        }
    }

    func promptForFolder() {
        presentingSystemPanel {
            let panel = NSOpenPanel()
            panel.title = "Add Folder"
            panel.message = "Choose a folder or file to keep in your dock."
            panel.canChooseDirectories = true
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = true
            if panel.runModal() == .OK {
                panel.urls.forEach { store.addFolder(at: $0) }
            }
        }
    }
}
