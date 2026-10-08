import Foundation

/// Turns scrolling over the dock into profile switches:
///
/// - A sideways two-finger swipe on a trackpad (or Magic Mouse) switches once per gesture,
///   after it has moved far enough, mostly sideways. Momentum after the fingers lift is
///   ignored, so a flick never skips a profile.
/// - With ⌘ held, scrolling in either direction switches, so a mouse wheel works too.
///   Wheels have no gestures; each notch can switch, at most once per `wheelInterval`.
///
/// Directions follow the scroll as the system reports it, with the user's scroll direction
/// already applied: scrolling toward content on the right or below (with natural
/// scrolling, fingers moving left or up) goes to the next profile, like turning a page.
public struct ProfileScrollGesture: Sendable {
    public enum Phase: Sendable {
        /// Fingers touched down and started moving.
        case began
        case changed
        /// Fingers lifted, the gesture was cancelled, or a new one may begin.
        case ended
        /// Not part of a gesture: a mouse wheel.
        case none
    }

    public struct Event: Sendable {
        public var deltaX: Double
        public var deltaY: Double
        public var phase: Phase
        /// Scrolling that continues on its own after a trackpad gesture ended.
        public var isMomentum: Bool
        public var isCommandDown: Bool
        public var timestamp: TimeInterval

        public init(deltaX: Double, deltaY: Double, phase: Phase, isMomentum: Bool = false, isCommandDown: Bool = false, timestamp: TimeInterval) {
            self.deltaX = deltaX
            self.deltaY = deltaY
            self.phase = phase
            self.isMomentum = isMomentum
            self.isCommandDown = isCommandDown
            self.timestamp = timestamp
        }
    }

    /// How far, in points, a trackpad gesture has to travel before it switches.
    public static let swipeDistance: Double = 36
    /// A swipe without ⌘ has to be at least this many times more sideways than vertical.
    public static let horizontalDominance: Double = 1.5
    public static let wheelInterval: TimeInterval = 0.3

    private var travelX: Double = 0
    private var travelY: Double = 0
    private var switchedThisGesture = false
    private var lastWheelSwitch: TimeInterval?

    public init() {}

    /// +1 for the next profile, -1 for the previous one, nil to stay.
    public mutating func handle(_ event: Event) -> Int? {
        guard !event.isMomentum else { return nil }
        switch event.phase {
        case .ended:
            resetGesture()
            return nil
        case .none:
            return wheelStep(event)
        case .began:
            resetGesture()
            fallthrough
        case .changed:
            travelX += event.deltaX
            travelY += event.deltaY
            guard !switchedThisGesture, let travel = gestureTravel(isCommandDown: event.isCommandDown),
                  abs(travel) >= Self.swipeDistance
            else { return nil }
            switchedThisGesture = true
            return Self.step(for: travel)
        }
    }

    private mutating func resetGesture() {
        travelX = 0
        travelY = 0
        switchedThisGesture = false
    }

    /// The distance along the axis that counts, or nil if the gesture doesn't count.
    private func gestureTravel(isCommandDown: Bool) -> Double? {
        if isCommandDown { return abs(travelX) >= abs(travelY) ? travelX : travelY }
        return abs(travelX) >= Self.horizontalDominance * abs(travelY) ? travelX : nil
    }

    private mutating func wheelStep(_ event: Event) -> Int? {
        let delta: Double
        if event.isCommandDown {
            delta = abs(event.deltaX) >= abs(event.deltaY) ? event.deltaX : event.deltaY
        } else if abs(event.deltaX) > abs(event.deltaY) {
            // A horizontal wheel (or Shift-scrolling) is a sideways swipe already.
            delta = event.deltaX
        } else {
            return nil
        }
        guard delta != 0 else { return nil }
        if let last = lastWheelSwitch, event.timestamp - last < Self.wheelInterval { return nil }
        lastWheelSwitch = event.timestamp
        return Self.step(for: delta)
    }

    /// Scroll deltas are positive toward content on the left or above.
    private static func step(for delta: Double) -> Int {
        delta < 0 ? 1 : -1
    }
}
