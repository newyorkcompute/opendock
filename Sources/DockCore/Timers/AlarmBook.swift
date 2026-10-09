import Foundation

/// The bookkeeping for every set alarm: when each rings next, which are ringing, and what
/// stopping, snoozing or a timeout does to them. Pure, so it can be tested: nothing here
/// sleeps or posts a notification. `TimerSessions` owns one, tells it the time, and does the
/// side effects its answers call for.
public struct AlarmBook: Equatable, Sendable {
    /// How long an alarm rings before giving up, if nobody stops it.
    public var ringDuration: TimeInterval

    /// When each set alarm goes off next. An alarm that is ringing isn't here until it's
    /// stopped or snoozed.
    public private(set) var armed: [UUID: Date] = [:]
    /// Alarms ringing right now, and since when.
    public private(set) var ringing: [UUID: Date] = [:]
    private var schedules: [UUID: AlarmSchedule] = [:]

    public init(ringDuration: TimeInterval = 90) {
        self.ringDuration = ringDuration
    }

    /// Every alarm set here, ringing or not.
    public var ids: Set<UUID> { Set(schedules.keys) }

    public func isSet(_ id: UUID) -> Bool { schedules[id] != nil }
    public func isRinging(_ id: UUID) -> Bool { ringing[id] != nil }
    public func schedule(for id: UUID) -> AlarmSchedule? { schedules[id] }

    // MARK: Setting and clearing

    /// Sets alarm `id` to `schedule`, or changes it. A changed time or repeat replaces a
    /// pending snooze; the same one keeps it. An alarm that is ringing keeps ringing, and
    /// the new schedule applies when it's stopped.
    public mutating func set(_ id: UUID, schedule: AlarmSchedule, now: Date, calendar: Calendar = .current) {
        let unchanged = schedules[id] == schedule
        schedules[id] = schedule
        if !unchanged || armed[id] == nil, ringing[id] == nil {
            armed[id] = schedule.nextFiring(after: now, calendar: calendar)
        }
    }

    /// Clears alarm `id`. Returns whether it was ringing, so the caller can silence it.
    @discardableResult
    public mutating func remove(_ id: UUID) -> Bool {
        schedules[id] = nil
        armed[id] = nil
        return ringing.removeValue(forKey: id) != nil
    }

    /// Clears every alarm not in `ids`. Returns the cleared alarms that were ringing.
    @discardableResult
    public mutating func removeAll(except ids: Set<UUID>) -> [UUID] {
        var wereRinging: [UUID] = []
        for id in self.ids.subtracting(ids).sorted(by: { $0.uuidString < $1.uuidString }) where remove(id) {
            wereRinging.append(id)
        }
        return wereRinging
    }

    // MARK: Ringing

    /// What stopping a ringing alarm did to it.
    public enum StopOutcome: Equatable, Sendable {
        /// A one-off alarm has rung: it should be turned off in its settings.
        case finished
        /// A repeating alarm is set again, for the date.
        case rearmed(Date)
    }

    /// Stops alarm `id` ringing. Nil when it wasn't ringing.
    @discardableResult
    public mutating func stop(_ id: UUID, now: Date, calendar: Calendar = .current) -> StopOutcome? {
        guard ringing.removeValue(forKey: id) != nil else { return nil }
        guard let schedule = schedules[id], schedule.repeats != .once,
            let next = schedule.nextFiring(after: now, calendar: calendar)
        else { return .finished }
        armed[id] = next
        return .rearmed(next)
    }

    /// Stops alarm `id` ringing and sets it to ring again in `minutes` (at least one).
    /// Returns when, or nil when it wasn't ringing.
    @discardableResult
    public mutating func snooze(_ id: UUID, minutes: Int, now: Date) -> Date? {
        guard ringing.removeValue(forKey: id) != nil else { return nil }
        let date = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        armed[id] = date
        return date
    }

    // MARK: Time

    /// The next moment something has to happen: an alarm going off, or one that has rung
    /// for `ringDuration` giving up. Nil when no alarm is set or ringing.
    public var nextDeadline: Date? {
        (armed.values + ringing.values.map { $0.addingTimeInterval(ringDuration) }).min()
    }

    /// What `advance(to:)` found had happened.
    public enum Event: Equatable, Sendable {
        /// The alarm's time came; it is ringing now.
        case rang(UUID)
        /// The alarm rang for `ringDuration` without being stopped, and was stopped as if
        /// by the user.
        case timedOut(UUID, StopOutcome)
    }

    /// Moves the clock to `now`: rings every alarm whose time has come, and stops those that
    /// have rung long enough. Alarms that rang just now don't time out in the same call.
    public mutating func advance(to now: Date, calendar: Calendar = .current) -> [Event] {
        var events: [Event] = []
        for (id, date) in armed.sorted(by: { $0.value < $1.value }) where date <= now {
            armed[id] = nil
            ringing[id] = now
            events.append(.rang(id))
        }
        for (id, since) in ringing.sorted(by: { $0.value < $1.value })
        where now.timeIntervalSince(since) >= ringDuration {
            if let outcome = stop(id, now: now, calendar: calendar) {
                events.append(.timedOut(id, outcome))
            }
        }
        return events
    }
}
