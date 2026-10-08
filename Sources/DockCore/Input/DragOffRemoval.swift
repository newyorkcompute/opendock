import CoreGraphics
import Foundation

/// Decides when a pinned item dragged off the dock is removed, with the semantics of
/// Apple's Dock: the item has to be well clear of the dock, and stay there for a moment,
/// before letting go removes it. A quick overshoot while reordering snaps the item back.
///
/// Once the hold completes the removal is *armed*: the dock closes the item's slot and the
/// dragged icon is labeled "Remove". Bringing the item back toward the dock disarms it and
/// the slot opens again; a release while armed removes the item, with a poof.
///
/// Pure bookkeeping over pointer samples, so it can be unit tested. The caller feeds it the
/// pointer's distance from the dock on every move, and again on a timer while the pointer
/// rests: a resting pointer produces no more events, and the timer is what notices that the
/// hold has lasted long enough.
public struct DragOffRemoval: Sendable {
    /// How long the pointer has to stay clear of the dock before letting go removes the
    /// item. Short, like Apple's Dock, but long enough that overshooting a reorder doesn't.
    public static let holdDuration: TimeInterval = 0.5

    /// The least distance from the dock that counts as clear of it, in points, whatever the
    /// icon size (see `threshold(iconSize:)`).
    public static let minimumThreshold: Double = 96

    /// Once armed, the pointer can come back to this fraction of the threshold before the
    /// removal disarms, so jitter right at the threshold doesn't flicker the label.
    static let disarmFraction = 0.75

    public enum Change: Equatable, Sendable {
        /// Nothing to do.
        case none
        /// The hold completed: close the item's slot and label the icon "Remove".
        case armed
        /// The pointer came back toward the dock: open the slot again and drop the label.
        case disarmed
    }

    /// When the pointer got clear of the dock; nil while it's near it.
    public private(set) var clearSince: TimeInterval?

    /// True once letting go removes the item.
    public private(set) var isArmed = false

    public init() {}

    /// Whether the pointer is clear of the dock, armed or not.
    public var isClear: Bool { clearSince != nil }

    /// How far from the dock the pointer has to be, in points: an icon and a half, but no
    /// less than `minimumThreshold` with small icons. About what Apple's Dock asks for.
    public static func threshold(iconSize: Double) -> Double {
        max(iconSize * 1.5, minimumThreshold)
    }

    /// Record how far the pointer is from the dock now.
    ///
    /// - Parameters:
    ///   - distance: Distance from the dock's hit zone, in points (see `distance(from:to:)`).
    ///   - threshold: Distance past which the pointer is clear (see `threshold(iconSize:)`).
    ///   - now: The sample's time; only differences matter.
    public mutating func pointerMoved(distance: Double, threshold: Double, now: TimeInterval) -> Change {
        let limit = isArmed ? threshold * Self.disarmFraction : threshold
        guard distance > limit else {
            clearSince = nil
            guard isArmed else { return .none }
            isArmed = false
            return .disarmed
        }
        guard let since = clearSince else {
            clearSince = now
            return .none
        }
        guard !isArmed, now - since >= Self.holdDuration else { return .none }
        isArmed = true
        return .armed
    }

    /// Forget everything, e.g. when the drag ends or comes back over the dock.
    public mutating func reset() {
        clearSince = nil
        isArmed = false
    }

    /// How far `point` is from `zone`: zero inside it, else the distance to its nearest
    /// point. Both in the same coordinates; the result works for a dock on any edge.
    public static func distance(from point: CGPoint, to zone: CGRect) -> Double {
        let dx = max(zone.minX - point.x, 0, point.x - zone.maxX)
        let dy = max(zone.minY - point.y, 0, point.y - zone.maxY)
        return Double((dx * dx + dy * dy).squareRoot())
    }
}
