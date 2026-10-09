import DockCore
import Foundation
import SystemServices

/// The live state of every time widget in the dock, keyed by the dock item that owns it, so
/// a tile's timer survives the tile being redrawn, magnified, or hidden with the dock.
/// Timers live in memory only: quitting OpenDock stops them. Settings (durations, the alarm
/// time) are the widget's and persist in `dock.json`.
///
/// Tiles register what they need (`updateFocusPlan`, `armAlarm`, `armCountdown`) and unregister
/// in `onDisappear`, so an alarm or countdown only fires while its tile is in the dock. One
/// task sleeps until the next thing that has to happen; the views do their own ticking for
/// display with `TimelineView`.
@Observable
final class TimerSessions {
    static let shared = TimerSessions()

    /// How a focus timer behaves when a phase ends, from its settings.
    struct FocusOptions: Equatable {
        var autoStart = false
        var notify = true
    }

    /// How long an alarm rings before giving up, if nobody stops it.
    static let ringDuration: TimeInterval = 90

    private(set) var focusTimers: [UUID: FocusTimer] = [:]
    private(set) var stopwatches: [UUID: Stopwatch] = [:]
    /// When each set alarm goes off next.
    private(set) var armedAlarms: [UUID: Date] = [:]
    /// Alarms ringing right now, and since when.
    private(set) var ringingAlarms: [UUID: Date] = [:]

    @ObservationIgnored private var focusOptions: [UUID: FocusOptions] = [:]
    @ObservationIgnored private var alarms: [UUID: AlarmArming] = [:]
    @ObservationIgnored private var countdowns: [UUID: CountdownArming] = [:]
    @ObservationIgnored private var sleeper: Task<Void, Never>?

    /// The current time; tests could swap it.
    @ObservationIgnored var now: () -> Date = Date.init

    private struct AlarmArming {
        var schedule: AlarmSchedule
        var label: String
        var sound: Bool
        /// Turns a one-off alarm off in its settings once it has rung.
        var disable: () -> Void
    }

    private struct CountdownArming {
        var target: Date
        var label: String
    }

    init() {}

    // MARK: Focus timer

    /// The timer for `id`, or a fresh one with `plan` when it hasn't been touched yet.
    func focusTimer(for id: UUID, plan: FocusTimer.Plan) -> FocusTimer {
        focusTimers[id] ?? FocusTimer(plan: plan)
    }

    /// Adopt the settings' durations and behavior. Call when the tile appears and whenever
    /// its settings change.
    func updateFocus(_ id: UUID, plan: FocusTimer.Plan, options: FocusOptions) {
        focusOptions[id] = options
        if var timer = focusTimers[id], timer.plan != plan {
            timer.setPlan(plan)
            focusTimers[id] = timer
        }
    }

    func toggleFocus(_ id: UUID, plan: FocusTimer.Plan) {
        var timer = focusTimer(for: id, plan: plan)
        timer.toggle(at: now())
        focusTimers[id] = timer
        if timer.isRunning, focusOptions[id]?.notify ?? true {
            WidgetNotifier.shared.requestAuthorizationIfNeeded()
        }
        reschedule()
    }

    func skipFocus(_ id: UUID, plan: FocusTimer.Plan) {
        var timer = focusTimer(for: id, plan: plan)
        timer.skip(at: now(), autoStart: focusOptions[id]?.autoStart ?? false)
        focusTimers[id] = timer
        reschedule()
    }

    func resetFocus(_ id: UUID, plan: FocusTimer.Plan) {
        var timer = focusTimer(for: id, plan: plan)
        if timer.isIdle { timer.resetCycle() } else { timer.reset() }
        focusTimers[id] = timer
        reschedule()
    }

    /// Forget a tile's timer, when its item leaves the dock.
    func removeFocus(_ id: UUID) {
        focusTimers[id] = nil
        focusOptions[id] = nil
        reschedule()
    }

    // MARK: Stopwatch

    func stopwatch(for id: UUID) -> Stopwatch {
        stopwatches[id] ?? Stopwatch()
    }

    func toggleStopwatch(_ id: UUID) {
        var stopwatch = stopwatch(for: id)
        stopwatch.toggle(at: now())
        stopwatches[id] = stopwatch
    }

    func lapStopwatch(_ id: UUID) {
        var stopwatch = stopwatch(for: id)
        stopwatch.lap(at: now())
        stopwatches[id] = stopwatch
    }

    func resetStopwatch(_ id: UUID) {
        stopwatches[id] = nil
    }

    // MARK: Alarm

    /// Set the alarm from its settings, or clear it (and silence it) with a nil `schedule`.
    /// Changing the label or sound of an alarm that's ringing doesn't interrupt it.
    func armAlarm(
        _ id: UUID, schedule: AlarmSchedule?, label: String, sound: Bool, disable: @escaping () -> Void
    ) {
        guard let schedule else {
            alarms[id] = nil
            armedAlarms[id] = nil
            if ringingAlarms[id] != nil { silence(id) }
            reschedule()
            return
        }
        let arming = AlarmArming(schedule: schedule, label: label, sound: sound, disable: disable)
        let unchanged = alarms[id].map { $0.schedule == schedule } ?? false
        alarms[id] = arming
        // A changed time or repeat replaces a pending snooze; the same one keeps it.
        if !unchanged || armedAlarms[id] == nil, ringingAlarms[id] == nil {
            armedAlarms[id] = schedule.nextFiring(after: now())
        }
        WidgetNotifier.shared.requestAuthorizationIfNeeded()
        reschedule()
    }

    /// Clear the alarm and silence it, when its tile leaves the dock.
    func removeAlarm(_ id: UUID) {
        alarms[id] = nil
        armedAlarms[id] = nil
        if ringingAlarms[id] != nil { silence(id) }
        reschedule()
    }

    func isRinging(_ id: UUID) -> Bool { ringingAlarms[id] != nil }

    /// Stop the ringing. A one-off alarm turns itself off; a repeating one sets itself for
    /// the next day it rings.
    func stopAlarm(_ id: UUID) {
        guard ringingAlarms[id] != nil else { return }
        silence(id)
        if let arming = alarms[id] {
            if arming.schedule.repeats == .once {
                arming.disable()
            } else {
                armedAlarms[id] = arming.schedule.nextFiring(after: now())
            }
        }
        reschedule()
    }

    /// Stop the ringing and ring again in `minutes`.
    func snoozeAlarm(_ id: UUID, minutes: Int) {
        guard ringingAlarms[id] != nil else { return }
        silence(id)
        armedAlarms[id] = now().addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        reschedule()
    }

    private func silence(_ id: UUID) {
        ringingAlarms[id] = nil
        WidgetNotifier.shared.withdraw(identifier: "alarm-\(id.uuidString)")
        if ringingAlarms.isEmpty { WidgetNotifier.shared.stopRinging() }
    }

    private func fireAlarm(_ id: UUID, at now: Date) {
        armedAlarms[id] = nil
        ringingAlarms[id] = now
        guard let arming = alarms[id] else { return }
        let time = arming.schedule.time.date(on: now, calendar: .current) ?? now
        WidgetNotifier.shared.post(
            title: arming.label.isEmpty ? "Alarm" : arming.label,
            body: time.formatted(date: .omitted, time: .shortened),
            identifier: "alarm-\(id.uuidString)",
            sound: arming.sound)
        if arming.sound { WidgetNotifier.shared.startRinging() }
    }

    // MARK: Countdown

    /// Notify when `target` arrives, or clear with a nil `target`. A target already in the
    /// past doesn't notify, so relaunching after the moment is quiet.
    func armCountdown(_ id: UUID, target: Date?, label: String) {
        guard let target, target > now() else {
            countdowns[id] = nil
            reschedule()
            return
        }
        countdowns[id] = CountdownArming(target: target, label: label)
        reschedule()
    }

    func removeCountdown(_ id: UUID) {
        countdowns[id] = nil
        reschedule()
    }

    // MARK: Scheduling

    /// The next moment something here has to happen.
    private var nextDeadline: Date? {
        var deadlines: [Date] = []
        for timer in focusTimers.values {
            if case let .running(endsAt) = timer.state { deadlines.append(endsAt) }
        }
        deadlines.append(contentsOf: armedAlarms.values)
        deadlines.append(contentsOf: ringingAlarms.values.map { $0.addingTimeInterval(Self.ringDuration) })
        deadlines.append(contentsOf: countdowns.values.map(\.target))
        return deadlines.min()
    }

    /// Sleep until the next deadline (or a minute, whichever is first, so a clock change or
    /// a wake from sleep is noticed), then do whatever is due.
    private func reschedule() {
        sleeper?.cancel()
        sleeper = nil
        guard let deadline = nextDeadline else { return }
        let delay = min(60, max(0, deadline.timeIntervalSince(now())))
        sleeper = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.sleeper = nil
            self.fireDue()
        }
    }

    private func fireDue() {
        let now = now()
        for (id, var timer) in focusTimers where timer.isRunning {
            let options = focusOptions[id] ?? FocusOptions()
            if let ended = timer.tick(at: now, autoStart: options.autoStart) {
                focusTimers[id] = timer
                if options.notify { notifyFocusPhaseEnded(id, ended: ended, timer: timer) }
            }
        }
        for (id, date) in armedAlarms where date <= now {
            fireAlarm(id, at: now)
        }
        for (id, since) in ringingAlarms where now.timeIntervalSince(since) >= Self.ringDuration {
            stopAlarm(id)
        }
        for (id, countdown) in countdowns where countdown.target <= now {
            countdowns[id] = nil
            WidgetNotifier.shared.post(
                title: countdown.label.isEmpty ? "Countdown" : countdown.label,
                body: "The time has come.",
                identifier: "countdown-\(id.uuidString)",
                sound: true)
            WidgetNotifier.shared.chime()
        }
        reschedule()
    }

    private func notifyFocusPhaseEnded(_ id: UUID, ended: FocusTimer.Phase, timer: FocusTimer) {
        let title = ended == .focus ? "Focus session over" : "Break over"
        let next = TimerFormatting.minutes(Int(timer.duration / 60))
        let body: String
        switch timer.phase {
        case .focus:
            body = "Back to focus: session \(timer.sessionNumber) of \(timer.plan.sessionsBeforeLongBreak), \(next)."
        case .shortBreak:
            body = "Time for a \(next) break."
        case .longBreak:
            body = "Cycle complete. Take a \(next) break."
        }
        WidgetNotifier.shared.post(title: title, body: body, identifier: "focus-\(id.uuidString)", sound: false)
        WidgetNotifier.shared.chime()
    }
}
