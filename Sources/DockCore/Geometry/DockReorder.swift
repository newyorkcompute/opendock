import Foundation

/// Where a drag over the dock would land, and the gap that previews it. Pure math, no UI,
/// so it can be unit tested.
///
/// While something is dragged over the dock, the row opens a gap where it would be
/// inserted; a reordered item leaves the row and the gap stands in for its slot. The gap
/// is a slot of its own, so it magnifies like an icon.
///
/// Positions are in the resting coordinates of the row *with* the gap (see
/// `DockMagnification`). The gap's width doesn't depend on where it is, so that frame
/// stays put while the gap moves: the insertion point can't feed back on itself and
/// flicker between two indices.
public enum DockReorder {
    /// Index among `slots` at which a drop at `pointer` inserts.
    ///
    /// The gap passes an item once the pointer is halfway between the item's center with
    /// the gap after it and its center with the gap before it, which is where the pointer
    /// leaves the gap. So the pointer is always over the gap.
    ///
    /// - Parameters:
    ///   - pointer: Pointer x relative to the row's center (the row is centered).
    ///   - slots: Resting widths of the row's slots, without the gap or the dragged item.
    ///   - gapWidth: Resting width of the gap.
    ///   - limit: Insertion points past this many leading slots are clamped to it; slots
    ///     after them (running apps that aren't pinned) can't take drops.
    public static func insertionIndex(pointer: Double, slots: [Double], gapWidth: Double, limit: Int) -> Int {
        let rowWidth = slots.reduce(0, +) + gapWidth
        // The pointer in the row without the gap, taking it as the gap's center. An item's
        // center there is exactly that halfway point.
        let target = pointer + rowWidth / 2 - gapWidth / 2
        var index = 0
        var leadingEdge = 0.0
        for width in slots.prefix(max(0, limit)) {
            guard leadingEdge + width / 2 < target else { break }
            leadingEdge += width
            index += 1
        }
        return index
    }

    /// Index at which an item added from a context menu on the dock is inserted: right
    /// after the item whose menu it was, else in the gap nearest the right-click, else at
    /// the end.
    ///
    /// - Parameters:
    ///   - anchor: Index of the item whose menu it was; nil for the dock's background menu.
    ///   - pointer: Right-click x relative to the row's center, as for `insertionIndex`.
    ///   - slots: Resting widths of the row's slots.
    ///   - limit: Number of pinned items, which lead the row; the result is at most this.
    public static func menuInsertionIndex(afterItemAt anchor: Int?, pointer: Double?, slots: [Double], limit: Int) -> Int {
        if let anchor { return min(max(anchor + 1, 0), max(0, limit)) }
        guard let pointer else { return max(0, limit) }
        return insertionIndex(pointer: pointer, slots: slots, gapWidth: 0, limit: limit)
    }

    /// The part of a gap standing at one insertion index.
    public struct GapPiece: Hashable, Sendable {
        /// Insertion index: the piece sits before the slot at this index.
        public var index: Int
        public var width: Double

        public init(index: Int, width: Double) {
            self.index = index
            self.width = width
        }
    }

    /// A gap of `width` at `position`, which is fractional while the gap animates from one
    /// insertion index to the next: all of it at an integer position, split between the two
    /// neighbors in between, so one opening grows exactly as the other closes.
    public static func gapPieces(position: Double, width: Double) -> [GapPiece] {
        guard width > 0 else { return [] }
        let position = max(0, position)
        let lower = position.rounded(.down)
        let fraction = position - lower
        let index = Int(lower)
        guard fraction > 1e-6 else { return [GapPiece(index: index, width: width)] }
        return [
            GapPiece(index: index, width: width * (1 - fraction)),
            GapPiece(index: index + 1, width: width * fraction),
        ]
    }
}
