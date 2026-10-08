import Foundation

/// Controlling the dock from the keyboard: a selection that moves along the row.
///
/// The shell starts a session with `begin` when the shortcut is pressed, feeds it the keys
/// it receives, and carries out the `Effect` each one returns. Arrow keys are translated
/// with `Key(arrow:edge:)` first, so the row reads the same way whichever screen edge the
/// dock is on: along the row is next and previous, across it does nothing.
///
/// `items` are the IDs of the selectable items in row order (spacers and dividers left
/// out). The caller passes the current list with every key, so items that come and go
/// (running apps, profile switches) never leave a dangling selection.
public struct DockKeyboardNavigation<ItemID: Hashable & Sendable>: Sendable, Equatable {
    public enum Arrow: Sendable {
        case up
        case down
        case left
        case right
    }

    /// A key press, already stripped of its direction on screen.
    public enum Key: Sendable, Equatable {
        case next
        case previous
        case first
        case last
        /// Return: open or activate the selected item.
        case activate
        /// Space: show what the item has to show, a folder's contents or a widget's popover.
        case secondary
        /// Delete: offer to remove the item from the dock.
        case remove
        case escape

        /// What an arrow key means on a dock along `edge`; nil when it points across the row.
        public init?(arrow: Arrow, edge: DockSettings.Edge) {
            switch (edge, arrow) {
            case (.bottom, .left), (.left, .up), (.right, .up): self = .previous
            case (.bottom, .right), (.left, .down), (.right, .down): self = .next
            case (.bottom, .up), (.bottom, .down), (.left, .left), (.left, .right), (.right, .left),
                (.right, .right):
                return nil
            }
        }
    }

    public enum Effect: Sendable, Equatable {
        /// The selection moved (or appeared) and should be shown and announced. `position` is
        /// 1-based, as in "3 of 8".
        case selected(ItemID, position: Int, count: Int)
        case activate(ItemID)
        case openSecondary(ItemID)
        case offerRemoval(ItemID)
        /// The session is over.
        case ended
        case none
    }

    /// True from `begin` until Escape or `end`, even while nothing is selectable.
    public private(set) var isActive = false
    public private(set) var selectedID: ItemID?
    /// Where the selection was, so it can land on a neighbor when its item disappears.
    private var selectedIndex = 0

    public init() {}

    /// Starts a session, selecting `preferred` if it's in the row (the item under the
    /// pointer, say), else the first item.
    public mutating func begin(items: [ItemID], preferring preferred: ItemID? = nil) -> Effect {
        isActive = true
        let index = preferred.flatMap { items.firstIndex(of: $0) } ?? 0
        return select(index: index, in: items)
    }

    public mutating func end() -> Effect {
        guard isActive else { return .none }
        isActive = false
        selectedID = nil
        return .ended
    }

    public mutating func handle(_ key: Key, items: [ItemID]) -> Effect {
        guard isActive else { return .none }
        if let selectedID, !items.contains(selectedID) {
            // The selected item went away; the key applies to the one in its place.
            _ = select(index: selectedIndex, in: items)
        }
        let index = selectedID.flatMap { items.firstIndex(of: $0) }
        switch key {
        case .next: return select(index: wrapped((index ?? -1) + 1, in: items), in: items)
        case .previous: return select(index: wrapped((index ?? items.count) - 1, in: items), in: items)
        case .first: return select(index: 0, in: items)
        case .last: return select(index: items.count - 1, in: items)
        case .activate: return selectedID.map(Effect.activate) ?? .none
        case .secondary: return selectedID.map(Effect.openSecondary) ?? .none
        case .remove: return selectedID.map(Effect.offerRemoval) ?? .none
        case .escape: return end()
        }
    }

    /// Moves the selection to `id`, as when the pointer comes to rest on another item.
    public mutating func select(_ id: ItemID, in items: [ItemID]) -> Effect {
        guard isActive, id != selectedID, let index = items.firstIndex(of: id) else { return .none }
        return select(index: index, in: items)
    }

    /// The row changed. If the selected item is gone, the selection moves to the item now
    /// at its place (or the last one), so Delete can clear a run of items.
    public mutating func itemsChanged(_ items: [ItemID]) -> Effect {
        guard isActive else { return .none }
        if let selectedID, let index = items.firstIndex(of: selectedID) {
            selectedIndex = index
            return .none
        }
        return select(index: selectedIndex, in: items)
    }

    private mutating func select(index: Int, in items: [ItemID]) -> Effect {
        guard !items.isEmpty else {
            selectedID = nil
            selectedIndex = 0
            return .none
        }
        let clamped = min(max(index, 0), items.count - 1)
        selectedIndex = clamped
        selectedID = items[clamped]
        return .selected(items[clamped], position: clamped + 1, count: items.count)
    }

    private func wrapped(_ index: Int, in items: [ItemID]) -> Int {
        guard !items.isEmpty else { return 0 }
        return ((index % items.count) + items.count) % items.count
    }
}
