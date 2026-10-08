import AppKit
import DockCore
import SwiftUI
import SystemServices

/// Removing a pinned item by dragging it off the dock, like Apple's Dock.
///
/// Once the item has been held well clear of the dock for a moment (`DragOffRemoval`
/// decides when), its slot closes up and the icon is labeled "Remove"; letting go then
/// removes it, with a puff of smoke and the system's poof sound. Letting go sooner, or
/// bringing it back, snaps it back into the row.
///
/// The dock's window gets no drag events once the drag has left it, so while a reorder is
/// off the dock a `DragOffOverlayPanel` covers the screen under the drag and reports it
/// (`dragOffUpdated`, `performDragOffDrop`); the drag-end watcher in
/// `DockController+Items.swift` feeds the pointer too, for a pointer resting in one place
/// or on another display. Running and recent apps that aren't pinned can't be dragged at
/// all, so only pinned items ever get here.
extension DockController {
    /// The drag left the dock (see `dragLeftDock`): put the overlay up, if it isn't yet,
    /// to follow the drag across the screen.
    func dragOffBegan() {
        guard let panel, let screen = targetScreen else { return }
        if let overlay = dragOffOverlay, overlay.ignoresMouseEvents {
            // Left over from the last removal, still showing its poof.
            dismissDragOffOverlay()
        }
        guard dragOffOverlay == nil else { return }
        let overlay = DragOffOverlayPanel(
            screen: screen, collectionBehavior: panel.collectionBehavior, controller: self)
        overlay.state.iconSize = store.settings.iconSize
        overlay.order(.below, relativeTo: panel.windowNumber)
        dragOffOverlay = overlay
    }

    /// The drag is over the overlay, here. Only a removal that's armed takes the drop;
    /// otherwise letting go is refused, and the icon slides back to the dock.
    func dragOffUpdated(_ info: any NSDraggingInfo) -> NSDragOperation {
        guard shellState.draggingItemID != nil, let overlay = dragOffOverlay else { return [] }
        dragOffPointerMoved(toScreen: overlay.convertPoint(toScreen: info.draggingLocation))
        return shellState.dragOffRemoval.isArmed ? .move : []
    }

    /// Where the pointer is now, in screen coordinates, while the drag is off the dock.
    func dragOffPointerMoved(toScreen point: NSPoint) {
        guard let dragged = shellState.draggingItemID, let overlay = dragOffOverlay else { return }
        let zone = hitZoneOnScreen ?? panel?.frame ?? .zero
        let change = shellState.dragOffRemoval.pointerMoved(
            distance: DragOffRemoval.distance(from: point, to: zone),
            threshold: DragOffRemoval.threshold(iconSize: store.settings.iconSize),
            now: ProcessInfo.processInfo.systemUptime
        )
        overlay.state.iconCenter = overlay.viewPoint(fromScreen: draggedIconCenter(pointer: point))
        switch change {
        case .armed:
            // The row closes up over the item's slot: it's leaving.
            withAnimation(.dockDropGap) {
                shellState.dropGap.open = 0
                overlay.state.isArmed = true
            }
        case .disarmed:
            reopenGap(for: dragged)
            withAnimation(.dockDropGap) { overlay.state.isArmed = false }
        case .none:
            break
        }
    }

    /// The drag is back over the dock (see `dragUpdated`): forget the hold, and if the
    /// removal was armed, open the item's slot again for the reorder to carry on.
    func dragOffReturned() {
        guard shellState.dragOffRemoval.isClear else { return }
        let wasArmed = shellState.dragOffRemoval.isArmed
        shellState.dragOffRemoval.reset()
        guard wasArmed else { return }
        if let overlay = dragOffOverlay {
            withAnimation(.dockDropGap) { overlay.state.isArmed = false }
        }
        if let dragged = shellState.draggingItemID { reopenGap(for: dragged) }
    }

    /// Let go on the overlay: remove the item if the removal is armed.
    func performDragOffDrop(_ info: any NSDraggingInfo) -> Bool {
        guard let dragged = shellState.draggingItemID, shellState.dragOffRemoval.isArmed,
            let overlay = dragOffOverlay
        else { return false }
        removeDraggedItem(dragged, pointer: overlay.convertPoint(toScreen: info.draggingLocation))
        return true
    }

    /// Let go away from the dock with no drop delivered (on another display, say, or
    /// over the dock's window but off the dock): a removal that's armed still removes;
    /// anything else just ends the drag.
    func dragOffReleased(atScreen point: NSPoint) {
        guard let dragged = shellState.draggingItemID, shellState.dragOffRemoval.isArmed else {
            endDrag()
            return
        }
        removeDraggedItem(dragged, pointer: point)
    }

    /// The drag ended, however it ended (see `endDrag`): take the overlay down, once any
    /// poof has played.
    func dragOffEnded() {
        shellState.dragOffRemoval.reset()
        guard let overlay = dragOffOverlay else { return }
        overlay.state.isArmed = false
        if overlay.state.poof == nil { dismissDragOffOverlay() }
    }

    func dismissDragOffOverlay() {
        shellState.dragOffPoofTask?.cancel()
        shellState.dragOffPoofTask = nil
        dragOffOverlay?.orderOut(nil)
        dragOffOverlay = nil
    }

    /// Takes `id` out of the dock, with the poof where its icon is. The row has already
    /// closed up over its slot, so nothing else moves.
    private func removeDraggedItem(_ id: DockItem.ID, pointer: NSPoint) {
        poof(at: draggedIconCenter(pointer: pointer))
        store.remove(id: id)
        endDrag()
        SystemSounds.playPoof()
    }

    /// Play the poof on the overlay, centered on `center` (in screen coordinates), and take
    /// the overlay down when it's over. From here on the overlay catches no events: the
    /// drag is done, and clicks must reach whatever is under it.
    private func poof(at center: NSPoint) {
        guard let overlay = dragOffOverlay else { return }
        overlay.stopReceivingEvents()
        overlay.state.poof = .init(
            center: overlay.viewPoint(fromScreen: center),
            size: store.settings.iconSize * 2.2,
            startedAt: .now
        )
        shellState.dragOffPoofTask?.cancel()
        shellState.dragOffPoofTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(PoofCloud.duration + 0.05))
            guard let self, !Task.isCancelled else { return }
            self.dismissDragOffOverlay()
        }
    }

    /// Where the dragged icon's center is on screen: the pointer, plus where on the icon
    /// it was picked up (`beginReorder` records that, in the layout's y-down coordinates).
    private func draggedIconCenter(pointer: NSPoint) -> NSPoint {
        let offset = shellState.dragGrabOffset
        return NSPoint(x: pointer.x + offset.x, y: pointer.y - offset.y)
    }

    /// Open the gap in the dragged item's own slot again, after a removal closed it.
    private func reopenGap(for dragged: DockItem.ID) {
        guard let index = store.items.firstIndex(where: { $0.id == dragged }) else { return }
        withAnimation(.dockDropGap) {
            shellState.dropGap.position = CGFloat(index)
            shellState.dropGap.open = 1
        }
    }
}
