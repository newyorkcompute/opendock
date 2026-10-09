import DockCore
import DockWidgetKit
import SwiftUI

// Four time widgets that share one model (`TimerSessions`) and one set of views. Each is its
// own `DockWidget`, so the widget library lists them separately and each has only the
// settings that apply to it. The settings keys are listed in `docs/widgets.md`.

/// A pomodoro-style timer: focus sessions, short breaks, and a long break after a cycle.
public enum FocusTimerWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.focusTimer
    public static let displayName = "Focus Timer"
    public static let systemImage = "timer"
    public static let summary = "Pomodoro-style focus sessions and breaks."
    public static let settingsSchema = FocusTimerSettings.schema

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(FocusTimerTileView(instance: instance))
    }

    public static func makePopout(instance: WidgetInstance) -> AnyView? {
        AnyView(FocusTimerPopoutView(instance: instance))
    }

    public static func makeSettingsView(instance: WidgetInstance) -> AnyView? {
        AnyView(FocusTimerSettingsView(instance: instance))
    }
}

/// Counts down to a date and time.
public enum CountdownWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.countdown
    public static let displayName = "Countdown"
    public static let systemImage = "hourglass"
    public static let summary = "Time left until a date."
    public static let settingsSchema = CountdownSettings.schema

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(CountdownTileView(instance: instance))
    }

    public static func makePopout(instance: WidgetInstance) -> AnyView? {
        AnyView(CountdownPopoutView(instance: instance))
    }

    public static func makeSettingsView(instance: WidgetInstance) -> AnyView? {
        AnyView(CountdownSettingsView(instance: instance))
    }
}

/// A stopwatch with laps.
public enum StopwatchWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.stopwatch
    public static let displayName = "Stopwatch"
    public static let systemImage = "stopwatch"
    public static let summary = "Elapsed time, with laps."
    public static let settingsSchema = StopwatchSettings.schema

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(StopwatchTileView(instance: instance))
    }

    public static func makePopout(instance: WidgetInstance) -> AnyView? {
        AnyView(StopwatchPopoutView(instance: instance))
    }

    public static func makeSettingsView(instance: WidgetInstance) -> AnyView? {
        AnyView(StopwatchSettingsView(instance: instance))
    }
}

/// An alarm that rings at a time of day, with a notification.
public enum AlarmWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.alarm
    public static let displayName = "Alarm"
    public static let systemImage = "alarm"
    public static let summary = "An alarm that rings at a time of day."
    public static let settingsSchema = AlarmSettings.schema

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(AlarmTileView(instance: instance))
    }

    public static func makePopout(instance: WidgetInstance) -> AnyView? {
        AnyView(AlarmPopoutView(instance: instance))
    }

    public static func makeSettingsView(instance: WidgetInstance) -> AnyView? {
        AnyView(AlarmSettingsView(instance: instance))
    }
}

// MARK: - Settings

/// The focus timer's settings keys, and typed access to one instance's values.
struct FocusTimerSettings {
    static let focusMinutes = WidgetSettingKey(
        "focusMinutes", type: .integer(1 ... 180), default: "25",
        summary: "Length of a focus session, in minutes.")
    static let shortBreakMinutes = WidgetSettingKey(
        "shortBreakMinutes", type: .integer(1 ... 60), default: "5",
        summary: "Length of the break after a focus session, in minutes.")
    static let longBreakMinutes = WidgetSettingKey(
        "longBreakMinutes", type: .integer(1 ... 120), default: "15",
        summary: "Length of the long break that ends a cycle, in minutes.")
    static let sessionsBeforeLongBreak = WidgetSettingKey(
        "sessionsBeforeLongBreak", type: .integer(1 ... 12), default: "4",
        summary: "Focus sessions in a cycle; the break after the last one is the long one.")
    static let autoStart = WidgetSettingKey(
        "autoStart", type: .bool, default: "false",
        summary: "Start the next focus session or break as soon as one ends.")
    static let notify = WidgetSettingKey(
        "notify", type: .bool, default: "true",
        summary: "Show a notification and play a sound when a session or break ends.")

    static let schema = WidgetSettingsSchema([
        focusMinutes, shortBreakMinutes, longBreakMinutes, sessionsBeforeLongBreak, autoStart, notify,
    ])

    let instance: WidgetInstance

    var plan: FocusTimer.Plan {
        FocusTimer.Plan(
            focus: TimeInterval(Self.focusMinutes.intValue(in: instance.settings) * 60),
            shortBreak: TimeInterval(Self.shortBreakMinutes.intValue(in: instance.settings) * 60),
            longBreak: TimeInterval(Self.longBreakMinutes.intValue(in: instance.settings) * 60),
            sessionsBeforeLongBreak: Self.sessionsBeforeLongBreak.intValue(in: instance.settings))
    }

    var options: TimerSessions.FocusOptions {
        TimerSessions.FocusOptions(
            autoStart: Self.autoStart.boolValue(in: instance.settings),
            notify: Self.notify.boolValue(in: instance.settings))
    }
}

/// The countdown's settings keys, and typed access to one instance's values.
struct CountdownSettings {
    static let date = WidgetSettingKey(
        "date", type: .text, default: "",
        summary:
            "The moment to count down to: ISO 8601 such as `\"2026-12-25T18:00:00Z\"`, or a date alone such as "
            + "`\"2026-12-25\"` for midnight. Empty means no date is set.")
    static let label = WidgetSettingKey(
        "label", type: .text, default: "",
        summary: "What the countdown is for, shown under the time left.")
    static let notify = WidgetSettingKey(
        "notify", type: .bool, default: "true",
        summary: "Show a notification and play a sound when the countdown reaches zero.")

    static let schema = WidgetSettingsSchema([date, label, notify])

    let instance: WidgetInstance

    /// The target, or nil when unset or unreadable.
    var target: Date? { CountdownTarget.parse(Self.date.value(in: instance.settings)) }
    var label: String { Self.label.value(in: instance.settings).trimmingCharacters(in: .whitespaces) }
    var notify: Bool { Self.notify.boolValue(in: instance.settings) }
}

/// The stopwatch's settings keys.
struct StopwatchSettings {
    static let showLaps = WidgetSettingKey(
        "showLaps", type: .bool, default: "true",
        summary: "Show the latest lap under the elapsed time.")

    static let schema = WidgetSettingsSchema([showLaps])

    let instance: WidgetInstance

    var showLaps: Bool { Self.showLaps.boolValue(in: instance.settings) }
}

/// The alarm's settings keys, and typed access to one instance's values.
struct AlarmSettings {
    static let enabled = WidgetSettingKey(
        "enabled", type: .bool, default: "false",
        summary: "Whether the alarm is set. A one-off alarm turns itself off once it has been stopped.")
    static let time = WidgetSettingKey(
        "time", type: .text, default: "07:00",
        summary: "When the alarm rings, as 24-hour `\"HH:mm\"`.")
    static let repeats = WidgetSettingKey(
        "repeats", type: .choice(AlarmRepeat.allCases.map(\.rawValue)), default: AlarmRepeat.once.rawValue,
        summary: "Which days the alarm rings.")
    static let label = WidgetSettingKey(
        "label", type: .text, default: "",
        summary: "A name for the alarm, shown in the tile and in the notification.")
    static let snoozeMinutes = WidgetSettingKey(
        "snoozeMinutes", type: .integer(1 ... 60), default: "9",
        summary: "How long Snooze waits before the alarm rings again.")
    static let sound = WidgetSettingKey(
        "sound", type: .bool, default: "true",
        summary: "Play a sound while the alarm rings, as well as showing a notification.")

    static let schema = WidgetSettingsSchema([enabled, time, repeats, label, snoozeMinutes, sound])

    let instance: WidgetInstance

    var isEnabled: Bool { Self.enabled.boolValue(in: instance.settings) }
    /// The configured time, or the default when the stored value doesn't parse.
    var time: AlarmTime {
        AlarmTime(parsing: Self.time.value(in: instance.settings))
            ?? AlarmTime(parsing: Self.time.defaultValue) ?? AlarmTime(hour: 7, minute: 0)
    }
    var repeats: AlarmRepeat { AlarmRepeat(rawValue: Self.repeats.value(in: instance.settings)) ?? .once }
    var label: String { Self.label.value(in: instance.settings).trimmingCharacters(in: .whitespaces) }
    var snoozeMinutes: Int { Self.snoozeMinutes.intValue(in: instance.settings) }
    var sound: Bool { Self.sound.boolValue(in: instance.settings) }

    var schedule: AlarmSchedule { AlarmSchedule(time: time, repeats: repeats) }
}
