import DockCore
import DockWidgetKit
import SwiftUI

/// How many reminders are waiting, and in which list, with the list itself a click away.
/// The settings keys are declared in `RemindersSettings` and listed in `docs/widgets.md`.
public enum RemindersWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.reminders
    public static let displayName = "Reminders"
    public static let systemImage = "checklist"
    public static let summary = "How many reminders are waiting, and the list to tick them off."
    public static let settingsSchema = RemindersSettings.schema

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(RemindersTileView(instance: instance))
    }

    public static func makePopout(instance: WidgetInstance) -> AnyView? {
        AnyView(RemindersPopoutView(instance: instance))
    }

    public static func makeSettingsView(instance: WidgetInstance) -> AnyView? {
        AnyView(RemindersSettingsView(instance: instance))
    }
}

/// The reminders widget's settings keys, and typed access to one instance's values.
struct RemindersSettings {
    /// Lists are picked by identifier so two lists with the same name stay apart. One that
    /// doesn't exist on this Mac, say in an imported layout, reads as every list.
    static let listID = WidgetSettingKey(
        "listID", type: .text, default: "",
        summary:
            "The identifier of the list to show, as chosen in Settings. Empty, or a list that doesn't exist on this Mac, means every list."
    )
    static let scope = WidgetSettingKey(
        "scope", type: .choice(ReminderScope.allCases.map(\.rawValue)), default: ReminderScope.all.rawValue,
        summary:
            "Which reminders the tile counts and the popover lists: every incomplete reminder, or only those due today or overdue."
    )
    static let showListName = WidgetSettingKey(
        "showListName", type: .bool, default: "true",
        summary: "Show the list's name under the count. When off, the tile is just the icon and the count.")

    static let schema = WidgetSettingsSchema([listID, scope, showListName])

    let instance: WidgetInstance

    var listID: String { Self.listID.value(in: instance.settings) }
    var scope: ReminderScope { ReminderScope(rawValue: Self.scope.value(in: instance.settings)) ?? .all }
    var showListName: Bool { Self.showListName.boolValue(in: instance.settings) }

    /// The chosen list among `lists`, or nil for every list.
    func list(in lists: [ReminderList]) -> ReminderList? {
        ReminderAgenda.selectedList(id: listID, in: lists)
    }

    /// The reminders this tile shows, unsorted.
    func items(from reminders: [ReminderItem], lists: [ReminderList], at now: Date) -> [ReminderItem] {
        ReminderAgenda.items(ReminderAgenda.items(reminders, in: list(in: lists)), in: scope, at: now)
    }
}
