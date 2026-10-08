import AppKit
import DockCore
import SwiftUI
import UniformTypeIdentifiers

/// Adding items from drops and open panels, and reordering.
extension DockController {
    /// Files dropped from Finder: `.app` bundles become apps, everything else a folder/file
    /// item. Inserted at `index` among the items, or appended; ones already in the dock are
    /// skipped.
    @discardableResult
    func handleDroppedURLs(_ urls: [URL], at index: Int? = nil) -> Bool {
        var insertion = index.map { min(max($0, 0), store.items.count) }
        var changed = false
        for url in addableURLs(urls) {
            let item: DockItem = url.pathExtension == "app" ? .app(at: url) : .folder(at: url)
            if let position = insertion {
                store.insert(item, at: position)
                insertion = position + 1
            } else {
                store.append(item)
            }
            changed = true
        }
        return changed
    }

    /// File URLs not yet in the dock, without duplicates.
    private func addableURLs(_ urls: [URL]) -> [URL] {
        var seen = Set(store.items.compactMap { $0.appItem?.url.normalizedPath ?? $0.folderItem?.url.normalizedPath })
        return urls.filter { $0.isFileURL && seen.insert($0.normalizedPath).inserted }
    }

    // MARK: - Drops (see `DockHostingView`)
    //
    // While a drag is over the dock, a gap opens where it would land and follows the
    // pointer (`DockReorder` places it). Reordering takes the dragged item out of the row,
    // the gap standing in for it, so the other items close up behind it and make room
    // ahead of it. Releasing commits the move; releasing away from the dock cancels.

    func dragUpdated(_ info: any NSDraggingInfo) -> NSDragOperation {
        guard let location = dropLocation(info) else { return [] }
        cancelScheduledHide()
        let isReorder = isReorderDrag(info)
        if isReorder {
            guard shellState.draggingItemID != nil || beginReorder(at: location) else { return [] }
        } else if addableURLs(droppedFileURLs(info)).isEmpty {
            return []
        }
        guard shellState.geometry.hitZone.contains(location) else {
            dragLeftDock()
            return []
        }
        stopWatchingForDragEnd()
        let width = isReorder ? shellState.dropGap.width : DockRowMetrics(settings: store.settings).dropGapWidth
        moveDropGap(to: dropIndex(at: location, gapWidth: width), width: width)
        pointerMoved(to: location)
        return isReorder ? .move : .copy
    }

    func dragExited() {
        dragLeftDock()
    }

    func performDrop(_ info: any NSDraggingInfo) -> Bool {
        guard let index = shellState.dropIndex else { return false }
        defer { endDrag() }
        guard isReorderDrag(info) else {
            return handleDroppedURLs(droppedFileURLs(info), at: index)
        }
        guard let dragged = shellState.draggingItemID else { return false }
        if store.items.firstIndex(where: { $0.id == dragged }) != index {
            store.move(id: dragged, to: index)
        }
        return true
    }

    func dragEnded() {
        endDrag()
    }

    /// Drags that start in the dock are items being reordered. Other drags from this app
    /// (such as rows of the Settings item list) are not; they carry no files either.
    private func isReorderDrag(_ info: any NSDraggingInfo) -> Bool {
        guard let source = info.draggingSource else { return false }
        if let view = source as? NSView { return view.window === panel }
        return true
    }

    /// The dragged item is the one under the drag when it first shows up: the drag starts
    /// a few points from where the mouse went down on it.
    private func beginReorder(at location: CGPoint) -> Bool {
        let geometry = shellState.geometry
        guard let id = geometry.anyItem(atX: location.x)?.pinnedID,
            let index = store.items.firstIndex(where: { $0.id == id }),
            let slot = geometry.restingSlots.first(where: { $0.id == .pinned(id) })
        else { return false }
        // The gap opens in the item's own slot, so nothing moves until the pointer does.
        shellState.draggingItemID = id
        shellState.dropGap = DockDropGap(position: CGFloat(index), open: 1, width: slot.width, growth: slot.growth)
        shellState.hoveredItemID = nil
        return true
    }

    /// Insertion index for a drop at `location`, among the pinned items other than the
    /// dragged one. Running apps that aren't pinned come after those and take no drops.
    private func dropIndex(at location: CGPoint, gapWidth: CGFloat) -> Int {
        let geometry = shellState.geometry
        let dragged = shellState.draggingItemID.map(DockRowItemID.pinned)
        let slots = geometry.restingSlots.filter { $0.id == nil || $0.id != dragged }
        let limit = slots.prefix { $0.id?.pinnedID != nil }.count
        return DockReorder.insertionIndex(
            pointer: Double(location.x - geometry.rowCenterX),
            slots: slots.map { Double($0.width) },
            gapWidth: Double(gapWidth),
            limit: limit
        )
    }

    private func moveDropGap(to index: Int, width: CGFloat) {
        shellState.dropIndex = index
        let target = CGFloat(index)
        // Only a gap for files opens from nothing (a reordered item's is open from the start).
        // Put it in place first, or it would sweep across the row from wherever it last was.
        // It opens on the next update (they keep coming while the drag rests), after this
        // one has been drawn.
        let closed = DockDropGap(position: target, open: 0, width: width)
        if shellState.dropGap.open == 0, shellState.dropGap != closed {
            shellState.dropGap = closed
            return
        }
        guard shellState.dropGap.position != target || shellState.dropGap.open != 1 else { return }
        withAnimation(.dockDropGap) {
            shellState.dropGap.position = target
            shellState.dropGap.open = 1
        }
    }

    /// The drag went off the dock. Dropping there does nothing: a reordered item's gap goes
    /// back to its own slot to show that, and a gap for files closes.
    private func dragLeftDock() {
        shellState.dropIndex = nil
        pointerMoved(to: nil)
        if let dragged = shellState.draggingItemID {
            if let index = store.items.firstIndex(where: { $0.id == dragged }),
                shellState.dropGap.position != CGFloat(index)
            {
                withAnimation(.dockDropGap) { shellState.dropGap.position = CGFloat(index) }
            }
            watchForDragEnd()
        } else if shellState.dropGap.open != 0 {
            withAnimation(.dockDropGap) { shellState.dropGap.open = 0 }
        }
    }

    /// Put the dragged item back in the row (where the gap was, after a drop) and close the
    /// gap, all at once: the row already looks like that, so nothing visibly moves.
    private func endDrag() {
        stopWatchingForDragEnd()
        guard shellState.isDragging || shellState.dropGap.open != 0 else { return }
        shellState.draggingItemID = nil
        shellState.dropIndex = nil
        shellState.dropGap.open = 0
        // Labels were off and the dock held still for the drag; carry on from wherever the
        // pointer is now.
        interactionEnded()
    }

    /// AppKit only tells a drag destination the drag ended if it ended over it, so a reorder
    /// released elsewhere would leave its item hidden. Watch the mouse button instead.
    private func watchForDragEnd() {
        guard shellState.dragEndWatcher == nil else { return }
        shellState.dragEndWatcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    self.endDrag()
                    return
                }
            }
        }
    }

    private func stopWatchingForDragEnd() {
        shellState.dragEndWatcher?.cancel()
        shellState.dragEndWatcher = nil
    }

    private func dropLocation(_ info: any NSDraggingInfo) -> CGPoint? {
        guard let panel else { return nil }
        return layoutPoint(fromScreen: panel.convertPoint(toScreen: info.draggingLocation))
    }

    private func droppedFileURLs(_ info: any NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL] ?? []
    }

    /// Items chosen in the open panel are inserted at `index` among the items, or appended.
    func promptForApp(at index: Int? = nil) {
        presentingSystemPanel {
            let panel = NSOpenPanel()
            panel.title = "Add App"
            panel.message = "Choose an application to add to your dock."
            panel.allowedContentTypes = [.application]
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            if panel.runModal() == .OK {
                handleDroppedURLs(panel.urls, at: index)
            }
        }
    }

    func promptForFolder(at index: Int? = nil) {
        presentingSystemPanel {
            let panel = NSOpenPanel()
            panel.title = "Add Folder"
            panel.message = "Choose a folder or file to keep in your dock."
            panel.canChooseDirectories = true
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = true
            if panel.runModal() == .OK {
                handleDroppedURLs(panel.urls, at: index)
            }
        }
    }
}
