import DockCore
import DockWidgetKit
import SwiftUI

/// How much of the year, month, week, and day has gone by, as bars or rings with a
/// percentage. The settings keys are declared in `TimeProgressSettings` and listed in
/// `docs/widgets.md`.
public enum TimeProgressWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.timeProgress
    public static let displayName = "Time Progress"
    public static let systemImage = "chart.bar.fill"
    public static let summary = "How much of the year, month, week, or day has passed."
    public static let settingsSchema = TimeProgressSettings.schema

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(TimeProgressTileView(instance: instance))
    }

    public static func makePopout(instance: WidgetInstance) -> AnyView? {
        AnyView(TimeProgressPopoutView())
    }

    public static func makeSettingsView(instance: WidgetInstance) -> AnyView? {
        AnyView(TimeProgressSettingsView(instance: instance))
    }
}

/// The widget's settings keys, and typed access to one instance's values.
struct TimeProgressSettings {
    /// How the tile draws each period.
    enum Style: String, CaseIterable {
        case bars
        case rings
    }

    static let showYear = WidgetSettingKey(
        "showYear", type: .bool, default: "true",
        summary: "Show how much of the year has passed.")
    static let showMonth = WidgetSettingKey(
        "showMonth", type: .bool, default: "true",
        summary: "Show how much of the month has passed.")
    static let showWeek = WidgetSettingKey(
        "showWeek", type: .bool, default: "false",
        summary: "Show how much of the week has passed. The week starts on the day your region's calendar says it does."
    )
    static let showDay = WidgetSettingKey(
        "showDay", type: .bool, default: "true",
        summary: "Show how much of the day has passed.")
    static let style = WidgetSettingKey(
        "style", type: .choice(Style.allCases.map(\.rawValue)), default: Style.bars.rawValue,
        summary:
            "Draw each period as a horizontal bar with its percentage beside it, or as a ring with the percentage under it."
    )

    static let schema = WidgetSettingsSchema([showYear, showMonth, showWeek, showDay, style])

    let instance: WidgetInstance

    /// The periods the tile shows, longest first. Never empty.
    var periods: [TimeProgressPeriod] {
        var enabled = Set<TimeProgressPeriod>()
        if Self.showYear.boolValue(in: instance.settings) { enabled.insert(.year) }
        if Self.showMonth.boolValue(in: instance.settings) { enabled.insert(.month) }
        if Self.showWeek.boolValue(in: instance.settings) { enabled.insert(.week) }
        if Self.showDay.boolValue(in: instance.settings) { enabled.insert(.day) }
        return TimeProgressPeriod.shown(enabled)
    }

    var style: Style {
        Style(rawValue: Self.style.value(in: instance.settings)) ?? .bars
    }
}
