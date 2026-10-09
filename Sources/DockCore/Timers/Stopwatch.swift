import Foundation

/// A stopwatch with laps. Pure bookkeeping over dates: the widget passes the current time
/// in and reads the elapsed time back, so nothing here needs a clock of its own.
public struct Stopwatch: Equatable, Sendable {
    public struct Lap: Equatable, Sendable, Identifiable {
        /// 1-based, in the order the laps were taken.
        public let number: Int
        /// This lap's own length.
        public let duration: TimeInterval
        /// Elapsed time when the lap was taken.
        public let total: TimeInterval

        public var id: Int { number }

        public init(number: Int, duration: TimeInterval, total: TimeInterval) {
            self.number = number
            self.duration = duration
            self.total = total
        }
    }

    public enum State: Equatable, Sendable {
        case idle
        /// Counting since `since`, on top of `accumulated` from earlier runs.
        case running(since: Date, accumulated: TimeInterval)
        case paused(elapsed: TimeInterval)
    }

    public private(set) var state: State = .idle
    /// Oldest first.
    public private(set) var laps: [Lap] = []

    public init() {}

    // MARK: Reading

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// False until the first start, and again after a reset.
    public var hasStarted: Bool { state != .idle }

    public func elapsed(at now: Date) -> TimeInterval {
        switch state {
        case .idle: 0
        case let .running(since, accumulated): accumulated + max(0, now.timeIntervalSince(since))
        case let .paused(elapsed): elapsed
        }
    }

    /// Time since the last lap was taken (or since the start).
    public func currentLap(at now: Date) -> TimeInterval {
        max(0, elapsed(at: now) - (laps.last?.total ?? 0))
    }

    /// The best and worst laps, for highlighting. Nil with fewer than two laps.
    public var fastestLap: Lap? { laps.count >= 2 ? laps.min { $0.duration < $1.duration } : nil }
    public var slowestLap: Lap? { laps.count >= 2 ? laps.max { $0.duration < $1.duration } : nil }

    // MARK: Controls

    public mutating func start(at now: Date) {
        switch state {
        case .idle: state = .running(since: now, accumulated: 0)
        case let .paused(elapsed): state = .running(since: now, accumulated: elapsed)
        case .running: break
        }
    }

    public mutating func stop(at now: Date) {
        guard case .running = state else { return }
        state = .paused(elapsed: elapsed(at: now))
    }

    /// Stop when running, otherwise start.
    public mutating func toggle(at now: Date) {
        if isRunning { stop(at: now) } else { start(at: now) }
    }

    /// Record a lap. Only while running: a stopped stopwatch has nothing new to record.
    @discardableResult
    public mutating func lap(at now: Date) -> Lap? {
        guard isRunning else { return nil }
        let total = elapsed(at: now)
        let lap = Lap(number: laps.count + 1, duration: currentLap(at: now), total: total)
        laps.append(lap)
        return lap
    }

    /// Back to zero with no laps.
    public mutating func reset() {
        state = .idle
        laps = []
    }
}
