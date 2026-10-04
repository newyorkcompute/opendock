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

    /// Item currently being dragged for reordering, if any.
    var draggingItemID: DockItem.ID?

    /// The item under the pointer, for the hover effect.
    var hoveredItemID: DockItem.ID?

    var isInteracting: Bool { interactionDepth > 0 }

    func beginInteraction() { interactionDepth += 1 }
    func endInteraction() { interactionDepth = max(0, interactionDepth - 1) }
}
