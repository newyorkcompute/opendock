import AppKit
import DockCore
import SwiftUI
import SystemServices
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
    // pointer (`DockReorder` places it). Dragging one of the row's own items takes it out
    // of the row, the gap standing in for it, so the other items close up behind it and
    // make room ahead of it. Releasing commits the move (or pins a running or recent app
    // where the gap is); releasing away from the dock cancels, unless the item was held
    // well away from it, which removes it (`DockController+DragOff.swift`). Over the Trash
    // the drop goes there instead (see `DockController+Trash.swift`), and over a widget
    // that takes it, to the widget (`DockController+WidgetDrops.swift`). What each kind of
    // item allows is decided by `DockRowDrag`.

    func dragUpdated(_ info: any NSDraggingInfo) -> NSDragOperation {
        guard let location = dropLocation(info) else { return [] }
        cancelScheduledHide()
        let isReorder = isReorderDrag(info)
        let files = isReorder ? [] : droppedFileURLs(info)
        // A widget may take what the dock itself can't, a link for instance.
        let widgetTarget = isReorder ? nil : widgetDropTarget(at: location, for: info)
        if isReorder {
            guard shellState.draggingRowID != nil || beginReorder(at: location) else { return [] }
        } else if files.isEmpty, widgetTarget == nil {
            dragLeftWidget()
            return []
        }
        guard shellState.geometry.hitZone.contains(location) else {
            dragLeftDock()
            return []
        }
        stopWatchingForDragEnd()
        dragOffReturned()
        if isTrashSlot(at: location) {
            dragLeftWidget()
            dragMovedOverTrash()
            pointerMoved(to: location)
            return isReorder ? .move : .generic
        }
        dragLeftTrash()
        if let widgetTarget {
            dragMovedOverWidget(widgetTarget)
            pointerMoved(to: location)
            return .generic
        }
        dragLeftWidget()
        pointerMoved(to: location)
        guard isReorder else {
            // Files already in the dock have nowhere to go in it but the Trash, or a widget.
            if addableURLs(files).isEmpty { return [] }
            let width = DockRowMetrics(settings: store.settings).dropGapWidth
            let index = fileDropIndex(at: location, gapWidth: width)
            shellState.dropIndex = index
            moveDropGap(to: index, width: width)
            return .copy
        }
        guard let dragged = shellState.draggingRowID, let placement = rowPlacement(at: location, for: dragged)
        else { return [] }
        shellState.rowPlacement = placement
        switch placement {
        case let .insert(index):
            moveDropGap(to: index, width: shellState.dropGap.width)
            return .move
        case let .home(index):
            // Nowhere to land: the gap waits in the item's own slot, and letting go here is
            // refused, so the icon slides back into it.
            moveDropGap(to: index, width: shellState.dropGap.width)
            return []
        }
    }

    func dragExited() {
        dragLeftDock()
    }

    func performDrop(_ info: any NSDraggingInfo) -> Bool {
        if shellState.isDragOverTrash {
            defer { endDrag() }
            return dropOnTrash(info, isReorder: isReorderDrag(info))
        }
        if let target = shellState.dropTargetItemID {
            defer { endDrag() }
            return dropOnWidget(target, info)
        }
        guard isReorderDrag(info) else {
            guard let index = shellState.dropIndex else { return false }
            defer { endDrag() }
            return handleDroppedURLs(droppedFileURLs(info), at: index)
        }
        guard let dragged = shellState.draggingRowID, let placement = shellState.rowPlacement else { return false }
        return finishDrag(of: dragged, at: .row(placement))
    }

    func dragEnded() {
        endDrag()
    }

    /// Let go of `dragged` at `target`: does what `DockRowDrag` says and ends the drag.
    /// Returns whether the drop was taken; a refused one slides the icon back to its slot.
    ///
    /// Changes to the row are made without animation: the gap already stands where a pinned
    /// or moved item lands, and the slot of a removed one has already closed, so the row
    /// looks the same before and after. Animating would only have the dragged item's old
    /// view shrink away from a slot it had already left.
    @discardableResult
    func finishDrag(of dragged: DockRowItemID, at target: DockRowDrag.Target) -> Bool {
        guard let item = dragged.dragItem else {
            endDrag()
            return false
        }
        let outcome = DockRowDrag.outcome(of: item, at: target)
        var taken = true
        withoutAnimation {
            switch outcome {
            case let .move(index):
                if let id = dragged.pinnedID, store.items.firstIndex(where: { $0.id == id }) != index {
                    store.move(id: id, to: index)
                }
            case let .pin(index):
                if let app = app(for: dragged) {
                    store.insert(DockItem(kind: .app(app)), at: index)
                } else {
                    taken = false
                }
            case .remove:
                if let id = dragged.pinnedID { store.remove(id: id) }
                SystemSounds.playPoof()
            case .forgetRecent:
                if let app = app(for: dragged) { store.removeRecentApp(app) }
                SystemSounds.playPoof()
            case .refuse:
                if case .trash = target { refuseTrashDrop() }
                taken = false
            case .cancel:
                taken = false
            }
            endDrag()
        }
        return taken
    }

    /// The app a dragged row item is: the pinned app, or the running or recent app.
    func app(for id: DockRowItemID) -> AppItem? {
        switch id {
        case let .pinned(pinnedID): store.profile.item(id: pinnedID)?.appItem
        case let .running(runningID): runningSection.first { $0.id == runningID }?.app
        case let .recent(recentID): recentSection.first { $0.id == recentID }?.app
        case .trash: nil
        }
    }

    /// Runs `body` with animations off, for changes the row has already made room for.
    func withoutAnimation(_ body: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }

    /// Drags that start in the dock are items of the row being dragged (a reorder, or a
    /// running or recent app on its way to being pinned). Other drags from this app are
    /// not: rows of the Settings item list carry no files, and files dragged out of a
    /// folder's popover are added like files from Finder.
    private func isReorderDrag(_ info: any NSDraggingInfo) -> Bool {
        guard let source = info.draggingSource else { return false }
        if let view = source as? NSView { return view.window === panel }
        return droppedFileURLs(info).isEmpty
    }

    /// The dragged item is the one under the drag when it first shows up: the drag starts
    /// a few points from where the mouse went down on it. Pinned items, running apps, and
    /// recent apps can all be dragged; the Trash can't.
    private func beginReorder(at location: CGPoint) -> Bool {
        let geometry = shellState.geometry
        guard let id = geometry.anyItem(at: location), id.dragItem != nil,
            let index = homeIndex(of: id),
            let slot = geometry.restingSlots.first(where: { $0.id == id })
        else { return false }
        // The gap opens in the item's own slot, so nothing moves until the pointer does.
        shellState.draggingRowID = id
        shellState.rowPlacement = .home(index)
        shellState.dropGap = DockDropGap(position: CGFloat(index), open: 1, width: slot.width, growth: slot.growth)
        shellState.hoveredItemID = nil
        // Where on the item it was picked up, for labeling the dragged icon off the dock.
        if let frame = geometry.itemFrames.first(where: { $0.id == id })?.frame {
            shellState.dragGrabOffset = CGPoint(x: frame.midX - location.x, y: frame.midY - location.y)
        } else {
            shellState.dragGrabOffset = .zero
        }
        return true
    }

    /// The dragged item's own place in the row: the index of its slot, which is also the
    /// insertion index among the slots without it. A pinned item's is its index among the
    /// pinned items, which lead the row; a running or recent app's comes from the last
    /// layout, and is nil once the app has left the row (it quit, say).
    func homeIndex(of id: DockRowItemID) -> Int? {
        if let pinnedID = id.pinnedID { return store.items.firstIndex { $0.id == pinnedID } }
        return shellState.geometry.restingSlots.firstIndex { $0.id == id }
    }

    /// Where `dragged` would land if let go at `location`, and so where the gap goes (see
    /// `DockRowDrag.placement`). Nil once the item has left the row.
    private func rowPlacement(at location: CGPoint, for dragged: DockRowItemID) -> DockRowDrag.Placement? {
        guard let item = dragged.dragItem, let home = homeIndex(of: dragged) else { return nil }
        let slots = rowSlots(without: dragged)
        return DockRowDrag.placement(
            of: item,
            insertionIndex: insertionIndex(at: location, slots: slots, gapWidth: shellState.dropGap.width, limit: nil),
            pinnedCount: slots.prefix { $0.id?.pinnedID != nil }.count,
            homeIndex: home
        )
    }

    /// Insertion index for files dropped at `location`, among the pinned items. The
    /// sections after them take no files.
    private func fileDropIndex(at location: CGPoint, gapWidth: CGFloat) -> Int {
        let slots = rowSlots(without: nil)
        let limit = slots.prefix { $0.id?.pinnedID != nil }.count
        return insertionIndex(at: location, slots: slots, gapWidth: gapWidth, limit: limit)
    }

    /// The row's resting slots, leaving out the dragged item's.
    private func rowSlots(without dragged: DockRowItemID?) -> [DockGeometry.Slot] {
        shellState.geometry.restingSlots.filter { $0.id == nil || $0.id != dragged }
    }

    /// Where among `slots` a drop at `location` inserts; clamped to `limit` leading slots,
    /// or to none of them.
    private func insertionIndex(at location: CGPoint, slots: [DockGeometry.Slot], gapWidth: CGFloat, limit: Int?)
        -> Int
    {
        let geometry = shellState.geometry
        return DockReorder.insertionIndex(
            pointer: Double(geometry.along(location) - geometry.rowCenter),
            slots: slots.map { Double($0.width) },
            gapWidth: Double(gapWidth),
            limit: limit ?? slots.count
        )
    }

    private func moveDropGap(to index: Int, width: CGFloat) {
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

    /// The drag went off the dock. Dropping there does nothing (unless it goes on to remove
    /// the item): a reordered item's gap goes back to its own slot to show that, and a gap
    /// for files closes.
    private func dragLeftDock() {
        shellState.dropIndex = nil
        shellState.rowPlacement = nil
        dragLeftTrash()
        dragLeftWidget()
        pointerMoved(to: nil)
        if let dragged = shellState.draggingRowID {
            // Once the removal is armed the slot has closed up, and stays closed.
            if !shellState.dragOffRemoval.isArmed, let index = homeIndex(of: dragged),
                shellState.dropGap.position != CGFloat(index)
            {
                withAnimation(.dockDropGap) { shellState.dropGap.position = CGFloat(index) }
            }
            dragOffBegan()
            watchForDragEnd()
        } else if shellState.dropGap.open != 0 {
            withAnimation(.dockDropGap) { shellState.dropGap.open = 0 }
        }
    }

    /// Put the dragged item back in the row (where the gap was, after a drop) and close the
    /// gap, all at once: the row already looks like that, so nothing visibly moves.
    func endDrag() {
        stopWatchingForDragEnd()
        dragOffEnded()
        guard
            shellState.isDragging || shellState.dropGap.open != 0 || shellState.isDragOverTrash
                || shellState.dropTargetItemID != nil
        else { return }
        shellState.draggingRowID = nil
        shellState.rowPlacement = nil
        shellState.dropIndex = nil
        shellState.dropGap.open = 0
        shellState.isDragOverTrash = false
        shellState.dropTargetItemID = nil
        // Labels were off and the dock held still for the drag; carry on from wherever the
        // pointer is now.
        interactionEnded()
    }

    /// AppKit only tells a drag destination the drag ended if it ended over it, so a reorder
    /// released elsewhere would leave its item hidden. Watch the mouse button instead.
    ///
    /// The same watch feeds the pointer to the removal (`dragOffPointerMoved`): the overlay
    /// does too while the drag is over it, but a pointer resting in one place sends few
    /// drag events, and one on another display sends none.
    private func watchForDragEnd() {
        guard shellState.dragEndWatcher == nil else { return }
        shellState.dragEndWatcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else { return }
                let location = NSEvent.mouseLocation
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    // Give a drop on the overlay a moment to arrive first: it ends the drag
                    // (and this watch) itself, with the icon staying put under the poof.
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    self.dragOffReleased(atScreen: location)
                    return
                }
                self.dragOffPointerMoved(toScreen: location)
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

    func droppedFileURLs(_ info: any NSDraggingInfo) -> [URL] {
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
