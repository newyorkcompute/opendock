import DockCore
import Foundation
import SystemServices

/// The live state of every time widget in the dock, keyed by the dock item that owns it, so
/// a tile's timer survives the tile being redrawn, magnified, or hidden with the dock.
/// Timers live in memory only: quitting OpenDock stops them. Settings (durations, the alarm
/// time) are the widget's and persist in `dock.json`.
///
/// Alarms and countdowns are set from the layout, not from the tiles: each widget's
/// `placementsChanged` hands over every enabled instance in the active profile
/// (`syncAlarms`, `syncCountdowns`), so an alarm rings whether or not its tile is drawn,
/// and stops being set when its item is removed or the profile switches away. Focus timers
/// and stopwatches are started from their tiles and kept across profile switches; they're
/// forgotten when their item is gone from every profile (`pruneFocusTimers`,
/// `pruneStopwatches`). One task sleeps until the next thing that has to happen; the views
/// do their own ticking for display with `WidgetTicking`.
@Observable
final class TimerSessions {
    static let shared = TimerSessions()

    /// How a focus timer behaves when a phase ends, from its settings.
    struct FocusOptions: Equatable {
        var autoStart = false
        var notify = true
    }

    /// Everything an enabled alarm tile asks for, from its settings.
    struct AlarmRequest {
        var id: UUID
        var schedule: AlarmSchedule
        var label: String
        var sound: Bool
        /// Turns a one-off alarm off in its settings once it has rung and been stopped.
        var disable: () -> Void
    }

    /// A countdown that wants a notification when `target` arrives.
    struct CountdownRequest {
        var id: UUID
        var target: Date
        var label: String
    }

    /// How long an alarm rings before giving up, if nobody stops it.
    static let ringDuration: TimeInterval = 90

    private(set) var focusTimers: [UUID: FocusTimer] = [:]
    private(set) var stopwatches: [UUID: Stopwatch] = [:]
    /// Which alarms are set, when each goes off next, and which are ringing.
    private(set) var alarmBook = AlarmBook(ringDuration: TimerSessions.ringDuration)

    /// When each set alarm goes off next.
    var armedAlarms: [UUID: Date] { alarmBook.armed }
    /// Alarms ringing right now, and since when.
    var ringingAlarms: [UUID: Date] { alarmBook.ringing }

    @ObservationIgnored private var focusOptions: [UUID: FocusOptions] = [:]
    @ObservationIgnored private var alarms: [UUID: AlarmDetails] = [:]
    @ObservationIgnored private var countdowns: [UUID: CountdownRequest] = [:]
    @ObservationIgnored private var sleeper: Task<Void, Never>?

    /// The current time; tests could swap it.
    @ObservationIgnored var now: () -> Date = Date.init

    /// What an alarm needs besides its schedule, which the book keeps.
    private struct AlarmDetails {
        var label: String
        var sound: Bool
        var disable: () -> Void
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

    /// Forget the timers of items that are gone from every profile.
    func pruneFocusTimers(keeping ids: Set<UUID>) {
        let gone = Set(focusTimers.keys).union(focusOptions.keys).subtracting(ids)
        guard !gone.isEmpty else { return }
        for id in gone {
            focusTimers[id] = nil
            focusOptions[id] = nil
        }
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

    /// Forget the stopwatches of items that are gone from every profile.
    func pruneStopwatches(keeping ids: Set<UUID>) {
        let gone = Set(stopwatches.keys).subtracting(ids)
        guard !gone.isEmpty else { return }
        for id in gone { stopwatches[id] = nil }
    }

    // MARK: Alarm

    /// Make the set alarms exactly `requests`: the enabled alarm tiles of the active profile.
    /// Any other alarm is cleared and, if it was ringing, silenced. Changing the label or
    /// sound of an alarm that's ringing doesn't interrupt it; see `AlarmBook.set` for what a
    /// changed time does. The notification permission is asked for only while `mayPrompt`,
    /// so an alarm that arrives in an imported layout waits for the welcome window to close.
    func syncAlarms(_ requests: [AlarmRequest], mayPrompt: Bool) {
        let now = self.now()
        let wereRinging = alarmBook.removeAll(except: Set(requests.map(\.id)))
        for id in wereRinging { silence(id) }
        alarms = [:]
        for request in requests {
            alarms[request.id] = AlarmDetails(label: request.label, sound: request.sound, disable: request.disable)
            alarmBook.set(request.id, schedule: request.schedule, now: now)
        }
        if mayPrompt, !requests.isEmpty {
            WidgetNotifier.shared.requestAuthorizationIfNeeded()
        }
        reschedule()
    }

    func isRinging(_ id: UUID) -> Bool { alarmBook.isRinging(id) }

    /// Stop the ringing. A one-off alarm turns itself off; a repeating one sets itself for
    /// the next day it rings.
    func stopAlarm(_ id: UUID) {
        guard let outcome = alarmBook.stop(id, now: now()) else { return }
        silence(id)
        finish(id, outcome)
        reschedule()
    }

    /// Stop the ringing and ring again in `minutes`.
    func snoozeAlarm(_ id: UUID, minutes: Int) {
        guard alarmBook.snooze(id, minutes: minutes, now: now()) != nil else { return }
        silence(id)
        reschedule()
    }

    private func finish(_ id: UUID, _ outcome: AlarmBook.StopOutcome) {
        if case .finished = outcome { alarms[id]?.disable() }
    }

    private func silence(_ id: UUID) {
        WidgetNotifier.shared.withdraw(identifier: "alarm-\(id.uuidString)")
        if alarmBook.ringing.isEmpty { WidgetNotifier.shared.stopRinging() }
    }

    private func ring(_ id: UUID, at now: Date) {
        guard let details = alarms[id], let schedule = alarmBook.schedule(for: id) else { return }
        let time = schedule.time.date(on: now, calendar: .current) ?? now
        WidgetNotifier.shared.post(
            title: details.label.isEmpty ? "Alarm" : details.label,
            body: time.formatted(date: .omitted, time: .shortened),
            identifier: "alarm-\(id.uuidString)",
            sound: details.sound)
        if details.sound { WidgetNotifier.shared.startRinging() }
    }

    // MARK: Countdown

    /// Make the set countdowns exactly `requests`: the countdown tiles of the active profile
    /// that have a date and want a notification. One whose target is already past doesn't
    /// notify, so relaunching after the moment is quiet.
    func syncCountdowns(_ requests: [CountdownRequest]) {
        let now = self.now()
        countdowns = Dictionary(
            requests.filter { $0.target > now }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        reschedule()
    }

    // MARK: Scheduling

    /// The next moment something here has to happen.
    private var nextDeadline: Date? {
        var deadlines: [Date] = []
        for timer in focusTimers.values {
            if case let .running(endsAt) = timer.state { deadlines.append(endsAt) }
        }
        if let alarm = alarmBook.nextDeadline { deadlines.append(alarm) }
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
        let now = self.now()
        for (id, var timer) in focusTimers where timer.isRunning {
            let options = focusOptions[id] ?? FocusOptions()
            if let ended = timer.tick(at: now, autoStart: options.autoStart) {
                focusTimers[id] = timer
                if options.notify { notifyFocusPhaseEnded(id, ended: ended, timer: timer) }
            }
        }
        for event in alarmBook.advance(to: now) {
            switch event {
            case let .rang(id):
                ring(id, at: now)
            case let .timedOut(id, outcome):
                silence(id)
                finish(id, outcome)
            }
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
