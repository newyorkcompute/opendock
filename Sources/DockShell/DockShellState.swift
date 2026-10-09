import DockCore
import Foundation
import Observation

/// Transient UI state shared between the controller and the SwiftUI views.
/// Nothing here is persisted.
@Observable
public final class DockShellState {
    /// True while the panel is on screen (not auto-hidden).
    public internal(set) var isVisible = true

    /// Number of open popovers/menus/sheets. While > 0 the dock will not auto-hide
    /// even if the pointer leaves it.
    var interactionDepth = 0

    /// The row item being dragged, if any: a pinned item being reordered, or a running or
    /// recent app on its way to being pinned (see `DockRowDrag`). It's hidden, and the drop
    /// gap stands in for it in the row.
    var draggingRowID: DockRowItemID?

    /// The gap that previews where the drag over the dock would land.
    var dropGap = DockDropGap()

    /// Where a drop now would insert, among the pinned items without the dragged one.
    /// Nil while no drag is over the dock (a reorder dragged out of it cancels on release),
    /// and while a running or recent app is over the sections after the pinned items,
    /// where it can't land (`DockRowDrag.Placement.home`).
    @ObservationIgnored var dropIndex: Int?

    /// Where the dragged row item would land now (see `DockRowDrag.Placement`): where the
    /// gap stands. Nil while the drag is off the dock, or over the Trash or a widget.
    @ObservationIgnored var rowPlacement: DockRowDrag.Placement?

    /// Notices a reorder released away from the dock, where the dock gets no drag events.
    @ObservationIgnored var dragEndWatcher: Task<Void, Never>?

    /// Whether letting go of the reorder away from the dock removes the item (see
    /// `DockController+DragOff.swift`).
    @ObservationIgnored var dragOffRemoval = DragOffRemoval()

    /// Where on the dragged item it was picked up: its center relative to the pointer, in
    /// the layout's coordinates, for placing the "Remove" label and the poof on the icon.
    @ObservationIgnored var dragGrabOffset: CGPoint = .zero

    /// Takes the drag-off overlay down once its poof has played.
    @ObservationIgnored var dragOffPoofTask: Task<Void, Never>?

    /// Where along the row the last right-click or control-click on the dock was, relative
    /// to the row's center, so items added from the menu it opened go there.
    @ObservationIgnored var contextClickOffset: CGFloat?

    /// True while a drag is over the Trash, which highlights it and takes the drop: a
    /// reordered item leaves the dock, files go to the Trash.
    var isDragOverTrash = false

    /// Counts the drops the Trash has refused; the Trash shakes its head each time it goes up.
    var trashShakes = 0

    /// The widget tile a drag is over that takes what it carries (the AirDrop tile, say),
    /// highlighted like the Trash; the drop goes to the widget (`DockController+WidgetDrops.swift`).
    var dropTargetItemID: DockItem.ID?

    var isDragging: Bool { draggingRowID != nil || dropIndex != nil }

    /// The item under the pointer, for its label.
    var hoveredItemID: DockRowItemID?

    /// Pointer position along the row (x on the bottom edge, y on a side), in the dock
    /// layout's coordinates. Kept after the pointer leaves so the row settles back around
    /// where it was, like Apple's Dock.
    var pointer: CGFloat?

    /// 0 ... 1, animated: how much of the configured magnification is applied.
    var magnification: CGFloat = 0

    /// True while the pointer is inside the dock's hit zone.
    var isPointerInside = false

    /// Side the newest profile's items slide in from: 1 from the right (the next profile),
    /// -1 from the left.
    var profileSwapDirection = 1

    /// The profile just switched to, named above the dock for a moment.
    var profileBanner: String?

    /// Icons bouncing while their apps launch.
    var launchBounces = LaunchBounces()

    /// The item the keyboard has selected, highlighted and labeled like the hovered one.
    /// Nil while the keyboard isn't controlling the dock.
    var keyboardSelection: DockRowItemID?

    /// Asks an item's view to show its popover (a folder's contents, a widget's popout) for
    /// the keyboard, which can't click it. Views compare the `item` and watch for changes.
    var popoverRequest: PopoverRequest?

    nonisolated struct PopoverRequest: Equatable, Sendable {
        var item: DockItem.ID
        /// Distinguishes repeated requests for the same item.
        var serial: Int
    }

    let geometry = DockGeometry()

    var isInteracting: Bool { interactionDepth > 0 }

    func beginInteraction() { interactionDepth += 1 }
    func endInteraction() { interactionDepth = max(0, interactionDepth - 1) }
}
