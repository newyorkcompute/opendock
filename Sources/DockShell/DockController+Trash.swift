import AppKit
import DockCore
import SystemServices
import os

/// The Trash at the end of the dock: its menu, and what dropping things on it does.
extension DockController {
    /// Whether `point` (layout coordinates) is on the Trash's slot along the row. Used for
    /// drags, which are over the dock wherever they are across it.
    func isTrashSlot(at point: CGPoint) -> Bool {
        store.showsTrash && shellState.geometry.anyItem(at: point) == .trash
    }

    /// Whether `point` (layout coordinates) is on the Trash's icon, for clicks.
    func isTrash(at point: CGPoint) -> Bool {
        store.showsTrash
            && shellState.geometry.itemFrames.contains { $0.id == .trash && $0.frame.contains(point) }
    }

    /// Called by the root view's `onChange(of: store.showsTrash)`: the Trash is only watched
    /// while the dock shows it.
    func trashShownChanged(_ shown: Bool) {
        if shown {
            trash.start()
        } else {
            trash.stop()
        }
    }

    func openTrash() {
        trash.open()
    }

    /// Opens the Trash's menu at `location` (screen coordinates), or at the pointer.
    func showTrashMenu(at location: NSPoint? = nil) {
        let location = location ?? NSEvent.mouseLocation
        // Start the menu's tracking loop after the event that asked for it has finished.
        Task { [weak self] in
            guard let self else { return }
            _ = trashMenu().popUp(positioning: nil, at: location, in: nil)
        }
    }

    /// Like the menu on Apple's Dock's Trash: Open, and Empty Trash, which Finder confirms.
    func trashMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = NSMenuItem(title: "Trash", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(actionMenuItem("Open") { [trash] in trash.open() })
        let empty = actionMenuItem("Empty Trash") { [trash] in trash.empty() }
        empty.isEnabled = !(trash.isKnown && trash.isEmpty)
        menu.addItem(empty)
        if trash.finderAccessDenied {
            menu.addItem(.separator())
            let allow = actionMenuItem("Allow Access to Finder…") { [trash] in trash.openAutomationSettings() }
            allow.toolTip =
                "OpenDock asks Finder whether the Trash is empty, and has Finder empty it. Allow it under Privacy & Security > Automation."
            menu.addItem(allow)
        }
        return menu
    }

    // MARK: - Drops

    /// A drag has come over the Trash. The gap it opened in the row stays where it is (the
    /// row would otherwise shift under the pointer and carry the Trash out from under it);
    /// the Trash's highlight says where the drop goes now.
    func dragMovedOverTrash() {
        shellState.dropIndex = nil
        if !shellState.isDragOverTrash { shellState.isDragOverTrash = true }
    }

    func dragLeftTrash() {
        if shellState.isDragOverTrash { shellState.isDragOverTrash = false }
    }

    /// A drop on the Trash. An item dragged out of the dock is removed from it (not from
    /// disk); files from Finder, or from a folder's popover, go to the Trash. Returns
    /// whether anything was taken.
    func dropOnTrash(_ info: any NSDraggingInfo, isReorder: Bool) -> Bool {
        if isReorder {
            guard let dragged = shellState.draggingItemID else { return false }
            store.remove(id: dragged)
            return true
        }
        return trashFiles(droppedFileURLs(info))
    }

    /// Moves `urls` to the Trash the way Finder does (`FileManager.trashItem`), so they can
    /// be put back. An app that's running stays where it is, as Finder would insist; the
    /// Trash shakes its head at it, and at anything else that couldn't be moved.
    @discardableResult
    func trashFiles(_ urls: [URL]) -> Bool {
        var trashed = false
        var refused = false
        for url in urls {
            if url.pathExtension == "app",
                running.isRunning(bundleIdentifier: Bundle(url: url)?.bundleIdentifier, bundleURL: url)
            {
                refused = true
                continue
            }
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashed = true
            } catch {
                trashLog.error(
                    "Couldn't move \(url.path, privacy: .public) to the Trash: \(error.localizedDescription)")
                refused = true
            }
        }
        if refused { refuseTrashDrop() }
        if trashed { trash.refresh() }
        return trashed
    }

    /// The Trash says no: a beep and a shake of the icon.
    func refuseTrashDrop() {
        NSSound.beep()
        shellState.trashShakes += 1
    }

    private var trashLog: Logger { Logger(subsystem: "com.newyorkcompute.opendock", category: "Trash") }
}
