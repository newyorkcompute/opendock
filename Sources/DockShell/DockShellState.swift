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

    /// Item currently being dragged for reordering, if any. It's hidden, and the drop gap
    /// stands in for it in the row.
    var draggingItemID: DockItem.ID?

    /// The gap that previews where the drag over the dock would land.
    var dropGap = DockDropGap()

    /// Where a drop now would insert, among the pinned items without the dragged one.
    /// Nil while no drag is over the dock (a reorder dragged out of it cancels on release).
    @ObservationIgnored var dropIndex: Int?

    /// Notices a reorder released away from the dock, where the dock gets no drag events.
    @ObservationIgnored var dragEndWatcher: Task<Void, Never>?

    /// Where the last right-click or control-click on the dock was, relative to the row's
    /// center, so items added from the menu it opened go there.
    @ObservationIgnored var contextClickX: CGFloat?

    var isDragging: Bool { draggingItemID != nil || dropIndex != nil }

    /// The item under the pointer, for its label.
    var hoveredItemID: DockRowItemID?

    /// Pointer x in the dock layout's coordinates. Kept after the pointer leaves so the
    /// row settles back around where it was, like Apple's Dock.
    var pointerX: CGFloat?

    /// 0 ... 1, animated: how much of the configured magnification is applied.
    var magnification: CGFloat = 0

    /// True while the pointer is inside the dock's hit zone.
    var isPointerInside = false

    /// Side the newest profile's items slide in from: 1 from the right (the next profile),
    /// -1 from the left.
    var profileSwapDirection = 1

    /// The profile just switched to, named above the dock for a moment.
    var profileBanner: String?

    let geometry = DockGeometry()

    var isInteracting: Bool { interactionDepth > 0 }

    func beginInteraction() { interactionDepth += 1 }
    func endInteraction() { interactionDepth = max(0, interactionDepth - 1) }
}
