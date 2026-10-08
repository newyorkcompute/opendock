import Foundation

/// Decides when a pointer held against the screen edge should reveal the dock over a
/// full-screen app, with the semantics of Apple's Dock: brushing the edge (overshooting
/// while reaching for a video's controls) does nothing; the pointer has to stay on the
/// edge for `duration`.
///
/// Pure bookkeeping over pointer samples, so it can be unit tested. The caller feeds it
/// every pointer move and runs a timer when told to: a resting pointer produces no more
/// events, so the timer is what notices that the hold has lasted long enough.
public struct EdgeHold: Sendable {
    /// How long the pointer has to stay on the edge, about what Apple's Dock takes.
    public static let duration: TimeInterval = 0.5

    public enum Change: Equatable, Sendable {
        /// Nothing to do.
        case none
        /// The pointer just arrived at the edge: check `isComplete` after `duration`.
        case began
        /// The pointer left the edge before the hold completed: stop the timer.
        case ended
    }

    /// When the pointer arrived at the edge; nil while it's elsewhere.
    public private(set) var startedAt: TimeInterval?

    public init() {}

    public var isHolding: Bool { startedAt != nil }

    /// Record where the pointer is now. Moving along the edge keeps the hold going; it only
    /// restarts after the pointer has left the edge.
    public mutating func pointerMoved(atEdge: Bool, now: TimeInterval) -> Change {
        switch (startedAt, atEdge) {
        case (nil, true):
            startedAt = now
            return .began
        case (.some, false):
            startedAt = nil
            return .ended
        case (nil, false), (.some, true):
            return .none
        }
    }

    /// Whether the pointer has stayed on the edge for `duration`. Call when the timer fires,
    /// after confirming the pointer is still at the edge.
    public func isComplete(now: TimeInterval) -> Bool {
        guard let startedAt else { return false }
        return now - startedAt >= Self.duration
    }

    /// Forget the current hold, e.g. once it revealed the dock or the Space changed.
    public mutating func reset() {
        startedAt = nil
    }
}
