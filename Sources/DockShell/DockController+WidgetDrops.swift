import AppKit
import DockCore
import DockWidgetKit

/// Widget tiles that take drops (`DockWidget.acceptsDrop(_:instance:)`), the AirDrop tile
/// for one. Like the Trash, such a tile is highlighted while a drag it would take is over
/// it, the gap in the row stays where it was, and the drop goes to the widget.
extension DockController {
    /// The widget tile under `point` (layout coordinates) that takes what `info` carries,
    /// if there is one. Reorders never land on a widget, only drags from outside the dock.
    func widgetDropTarget(at point: CGPoint, for info: any NSDraggingInfo) -> DockItem.ID? {
        guard let id = shellState.geometry.anyItem(at: point)?.pinnedID,
            let instance = store.items.first(where: { $0.id == id })?.widgetInstance
        else { return nil }
        return registry.acceptsDrop(WidgetDrop(pasteboard: info.draggingPasteboard), on: instance) ? id : nil
    }

    func dragMovedOverWidget(_ id: DockItem.ID) {
        shellState.dropIndex = nil
        if shellState.dropTargetItemID != id { shellState.dropTargetItemID = id }
    }

    func dragLeftWidget() {
        if shellState.dropTargetItemID != nil { shellState.dropTargetItemID = nil }
    }

    /// Hands the drop to the widget under it. A beep when it won't take it after all.
    func dropOnWidget(_ id: DockItem.ID, _ info: any NSDraggingInfo) -> Bool {
        guard let instance = store.items.first(where: { $0.id == id })?.widgetInstance else { return false }
        let taken = registry.performDrop(WidgetDrop(pasteboard: info.draggingPasteboard), on: instance)
        if !taken { NSSound.beep() }
        return taken
    }
}
