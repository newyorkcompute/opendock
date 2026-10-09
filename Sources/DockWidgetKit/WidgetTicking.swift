import SwiftUI

/// Redraws its content with the current date every `interval` seconds while `active` and
/// the dock is on screen. Hidden or inactive, it ticks about once an hour instead and
/// redraws as soon as it's needed again, so a tile that was off screen for a while is
/// current the moment the dock slides back in.
///
/// Ticks fall on whole multiples of the interval, so a clock's digits change on the second
/// and the schedule doesn't restart every time the tile's body runs (which it does on every
/// frame of magnification).
///
/// ```swift
/// WidgetTicking(interval: 60) { now in
///     WidgetPrimaryText(now.formatted(date: .omitted, time: .shortened))
/// }
/// ```
public struct WidgetTicking<Content: View>: View {
    private let interval: TimeInterval
    private let active: Bool
    private let content: (Date) -> Content

    @Environment(\.dockIsVisible) private var isVisible

    /// - Parameters:
    ///   - interval: Seconds between redraws while ticking, such as 1 for a running timer
    ///     or 60 for a clock without seconds.
    ///   - active: Whether the content changes on its own right now. Pass false for a
    ///     paused timer or an alarm that's off; the view then only catches up hourly.
    ///   - content: Builds the view for a date; called on each tick.
    public init(interval: TimeInterval, active: Bool = true, @ViewBuilder content: @escaping (Date) -> Content) {
        self.interval = interval
        self.active = active
        self.content = content
    }

    public var body: some View {
        let period = WidgetTickSchedule.period(interval: interval, active: active, visible: isVisible)
        TimelineView(.periodic(from: WidgetTickSchedule.start(for: period), by: period)) { context in
            content(context.date)
        }
    }
}

/// The arithmetic behind `WidgetTicking`, kept separate so it can be tested.
public enum WidgetTickSchedule {
    /// How often to redraw while the content isn't ticking: hidden off screen, or inactive.
    public static let idleInterval: TimeInterval = 3600

    /// The interval to tick at: `interval` while active and visible, otherwise the idle one.
    public static func period(interval: TimeInterval, active: Bool, visible: Bool) -> TimeInterval {
        active && visible ? interval : idleInterval
    }

    /// The most recent whole multiple of `period` at or before `now`. Using it as a periodic
    /// schedule's start keeps ticks on round boundaries and makes the start stable across
    /// re-renders within one period.
    public static func start(for period: TimeInterval, now: Date = .now) -> Date {
        Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / period).rounded(.down) * period)
    }
}
