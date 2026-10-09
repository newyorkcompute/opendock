import Foundation

/// What dragging an item of the dock row does, with the semantics of Apple's Dock. Pure
/// decisions over what kind of item it is and where it's let go, so they can be unit
/// tested; the dock shell maps its row items and drag state onto these.
///
/// Pinned items are moved among the pinned items, and removed by dropping them on the
/// Trash or holding them off the dock. A running app that isn't pinned can be dragged
/// into the pinned items to pin it where it lands; anywhere else it springs back, since a
/// running app can't be made to go away by dragging. A recent app pins the same way, and
/// is forgotten (with a poof) when dropped on the Trash or held off the dock.
public enum DockRowDrag {
    /// What kind of row item is being dragged.
    public enum Item: Hashable, Sendable {
        /// One of the pinned items.
        case pinned
        /// A running app that isn't pinned, in the section after the pinned items.
        case running
        /// A recently used app that is neither pinned nor running, after the running apps.
        case recent
    }

    /// Where the gap stands while the item is dragged over the dock's row, and what a drop
    /// there does.
    public enum Placement: Hashable, Sendable {
        /// Letting go inserts the item at this index among the pinned items; the gap
        /// previews it there.
        case insert(Int)
        /// Letting go does nothing: the pointer is over the sections after the pinned items,
        /// where a running or recent app can't land. The gap stays at the item's own slot,
        /// which is this index in the row.
        case home(Int)
    }

    /// Where the drag is when it's let go.
    public enum Target: Hashable, Sendable {
        /// Over the row, where the gap stands.
        case row(Placement)
        /// Over the Trash at the end of the dock.
        case trash
        /// Away from the dock. `armed` says whether it was held there long enough that
        /// letting go removes the item (see `DragOffRemoval`).
        case offDock(armed: Bool)
    }

    /// What letting go does.
    public enum Outcome: Hashable, Sendable {
        /// Move the pinned item to this index among the pinned items.
        case move(to: Int)
        /// Pin the running or recent app at this index among the pinned items.
        case pin(at: Int)
        /// Take the pinned item out of the dock, with a poof.
        case remove
        /// Forget the recent app, with a poof.
        case forgetRecent
        /// Say no: the icon springs back to its slot, and if it was dropped on the Trash,
        /// the Trash shakes its head.
        case refuse
        /// Nothing happens; the icon springs back to its slot.
        case cancel
    }

    /// Where the gap goes while `item` is dragged over the row.
    ///
    /// - Parameters:
    ///   - insertionIndex: Where among all the row's slots (without the dragged item) the
    ///     pointer would insert, unclamped (see `DockReorder.insertionIndex`).
    ///   - pinnedCount: How many of those slots lead the row as pinned items. Insertion
    ///     indices up to this one are among the pinned items.
    ///   - homeIndex: The dragged item's own place in the row, as an insertion index among
    ///     the slots without it.
    public static func placement(of item: Item, insertionIndex: Int, pinnedCount: Int, homeIndex: Int) -> Placement {
        let limit = max(0, pinnedCount)
        switch item {
        case .pinned:
            // Pinned items stay among the pinned items: past them the gap sits at their end.
            return .insert(min(max(0, insertionIndex), limit))
        case .running, .recent:
            // Over the pinned items the app is about to be pinned; past them it isn't going
            // anywhere, and its own slot waits for it.
            return insertionIndex <= limit ? .insert(max(0, insertionIndex)) : .home(max(0, homeIndex))
        }
    }

    /// Whether holding `item` away from the dock arms its removal, so that letting go
    /// removes it. A running app never arms: it springs back without so much as a label.
    public static func removesWhenDraggedOff(_ item: Item) -> Bool {
        switch item {
        case .pinned, .recent: true
        case .running: false
        }
    }

    /// What letting go of `item` at `target` does.
    public static func outcome(of item: Item, at target: Target) -> Outcome {
        switch (item, target) {
        case let (.pinned, .row(.insert(index))):
            return .move(to: index)
        case let (.running, .row(.insert(index))), let (.recent, .row(.insert(index))):
            return .pin(at: index)
        case (_, .row(.home)):
            return .cancel
        case (.pinned, .trash):
            return .remove
        case (.recent, .trash):
            return .forgetRecent
        case (.running, .trash):
            return .refuse
        case (_, .offDock(armed: false)):
            return .cancel
        case (.pinned, .offDock(armed: true)):
            return .remove
        case (.recent, .offDock(armed: true)):
            return .forgetRecent
        case (.running, .offDock(armed: true)):
            // Never armed (see `removesWhenDraggedOff`), but still nothing to do.
            return .refuse
        }
    }
}
