import Foundation

/// A pomodoro-style focus timer: focus sessions separated by short breaks, with a long
/// break after every few sessions. Pure bookkeeping over dates so it can be unit tested;
/// the widget feeds it the current time and runs a ticker while it's running.
public struct FocusTimer: Equatable, Sendable {
    /// How long each phase lasts and how many focus sessions make a cycle.
    public struct Plan: Equatable, Sendable {
        public var focus: TimeInterval
        public var shortBreak: TimeInterval
        public var longBreak: TimeInterval
        /// Focus sessions before a long break instead of a short one. At least 1.
        public var sessionsBeforeLongBreak: Int

        public init(
            focus: TimeInterval = 25 * 60, shortBreak: TimeInterval = 5 * 60, longBreak: TimeInterval = 15 * 60,
            sessionsBeforeLongBreak: Int = 4
        ) {
            self.focus = max(1, focus)
            self.shortBreak = max(1, shortBreak)
            self.longBreak = max(1, longBreak)
            self.sessionsBeforeLongBreak = max(1, sessionsBeforeLongBreak)
        }

        public func duration(of phase: Phase) -> TimeInterval {
            switch phase {
            case .focus: focus
            case .shortBreak: shortBreak
            case .longBreak: longBreak
            }
        }
    }

    public enum Phase: Equatable, Sendable {
        case focus
        case shortBreak
        case longBreak

        public var isBreak: Bool { self != .focus }

        /// "Focus", "Break", "Long break".
        public var title: String {
            switch self {
            case .focus: "Focus"
            case .shortBreak: "Break"
            case .longBreak: "Long break"
            }
        }
    }

    public enum State: Equatable, Sendable {
        /// The phase hasn't started; its full duration remains.
        case idle
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
    }

    public var plan: Plan
    public private(set) var phase: Phase = .focus
    public private(set) var state: State = .idle
    /// Focus sessions completed since the timer was last reset. The position in the current
    /// cycle is this modulo `plan.sessionsBeforeLongBreak`.
    public private(set) var completedSessions = 0

    public init(plan: Plan = Plan()) {
        self.plan = plan
    }

    // MARK: Reading

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    public var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    public var isIdle: Bool { state == .idle }

    /// The current phase's full length.
    public var duration: TimeInterval { plan.duration(of: phase) }

    /// Seconds left in the current phase, never negative.
    public func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .idle: duration
        case let .running(endsAt): max(0, endsAt.timeIntervalSince(now))
        case let .paused(remaining): max(0, remaining)
        }
    }

    /// 1 at the start of a phase, 0 when it ends: the ring's filled fraction.
    public func fractionRemaining(at now: Date) -> Double {
        min(1, max(0, remaining(at: now) / duration))
    }

    /// 1-based number of the current (or next) focus session within its cycle, for
    /// "Focus 2 of 4". During a break it's the session that comes next.
    public var sessionNumber: Int {
        completedSessions % plan.sessionsBeforeLongBreak + 1
    }

    /// Whether the phase has run out at `now`.
    public func isComplete(at now: Date) -> Bool {
        if case let .running(endsAt) = state { return endsAt <= now }
        return false
    }

    // MARK: Controls

    /// Start the phase, or resume it when paused. Running timers are left alone.
    public mutating func start(at now: Date) {
        switch state {
        case .idle: state = .running(endsAt: now.addingTimeInterval(duration))
        case let .paused(remaining): state = .running(endsAt: now.addingTimeInterval(remaining))
        case .running: break
        }
    }

    public mutating func pause(at now: Date) {
        guard case .running = state else { return }
        state = .paused(remaining: remaining(at: now))
    }

    /// Pause when running, otherwise start.
    public mutating func toggle(at now: Date) {
        if isRunning { pause(at: now) } else { start(at: now) }
    }

    /// Back to the start of the current phase, stopped.
    public mutating func reset() {
        state = .idle
    }

    /// Back to the first focus session, stopped.
    public mutating func resetCycle() {
        phase = .focus
        completedSessions = 0
        state = .idle
    }

    /// End the current phase now and move on to the next: a break after focus (the long
    /// one when the cycle is complete), focus after a break. Returns the phase that ended.
    @discardableResult
    public mutating func skip(at now: Date, autoStart: Bool) -> Phase {
        let ended = phase
        switch phase {
        case .focus:
            completedSessions += 1
            phase = completedSessions.isMultiple(of: plan.sessionsBeforeLongBreak) ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            phase = .focus
        }
        state = autoStart ? .running(endsAt: now.addingTimeInterval(duration)) : .idle
        return ended
    }

    /// Call once a second while running. When the phase has run out, moves on (see
    /// `skip`) and returns the phase that ended, so the caller can notify.
    @discardableResult
    public mutating func tick(at now: Date, autoStart: Bool) -> Phase? {
        guard isComplete(at: now) else { return nil }
        return skip(at: now, autoStart: autoStart)
    }

    /// Adopt new durations. A phase that hasn't started picks up its new length at once;
    /// a running or paused one keeps counting down what it had.
    public mutating func setPlan(_ newPlan: Plan) {
        plan = newPlan
    }
}
