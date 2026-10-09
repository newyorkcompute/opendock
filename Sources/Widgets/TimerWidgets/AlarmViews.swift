import DockCore
import DockWidgetKit
import SwiftUI

/// The in-dock alarm tile: a bell, the alarm time, and its name or when it next rings. While
/// it rings, the bell pulses and Snooze and Stop buttons appear.
struct AlarmTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var sessions = TimerSessions.shared

    private var settings: AlarmSettings { AlarmSettings(instance: instance) }
    private var id: UUID { updater.id }

    var body: some View {
        let settings = self.settings
        let ringing = sessions.isRinging(id)
        let next = sessions.armedAlarms[id]
        WidgetTicking(interval: 60, active: settings.isEnabled) { now in
            WidgetTile {
                WidgetStack(spacing: iconSize * (edge.isVertical ? 0.06 : 0.14)) {
                    bell(ringing: ringing, enabled: settings.isEnabled)
                    VStack(alignment: edge.isVertical ? .center : .leading, spacing: 0) {
                        WidgetPrimaryText(TimerStyle.timeOfDay(settings.time, on: now))
                        WidgetSecondaryText(AlarmText.caption(settings, ringing: ringing, next: next, now: now))
                    }
                    if ringing {
                        HStack(spacing: iconSize * (edge.isVertical ? 0.04 : 0.1)) {
                            TimerButton(
                                symbol: "zzz", size: iconSize * 0.28, label: "Snooze", compact: edge.isVertical
                            ) {
                                sessions.snoozeAlarm(id, minutes: settings.snoozeMinutes)
                            }
                            TimerButton(
                                symbol: "stop.fill", size: iconSize * 0.28, label: "Stop", compact: edge.isVertical
                            ) {
                                sessions.stopAlarm(id)
                            }
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                "Alarm \(TimerStyle.timeOfDay(settings.time, on: now)), "
                    + AlarmText.caption(settings, ringing: ringing, next: next, now: now))
        }
        .onAppear(perform: arm)
        .onChange(of: instance.settings) { arm() }
        .onDisappear { sessions.removeAlarm(id) }
    }

    private func bell(ringing: Bool, enabled: Bool) -> some View {
        let style =
            ringing
            ? AnyShapeStyle(Color.orange)
            : enabled ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(HierarchicalShapeStyle.secondary)
        return Image(systemName: ringing ? "bell.and.waves.left.and.right.fill" : enabled ? "alarm.fill" : "alarm")
            .font(.system(size: iconSize * 0.36, weight: .semibold))
            .foregroundStyle(style)
            .symbolEffect(.pulse, options: .repeating, isActive: ringing)
            .accessibilityHidden(true)
    }

    /// Set or clear the alarm from the settings. The closure turns a one-off alarm off in
    /// its settings once it has rung and been stopped.
    private func arm() {
        let settings = self.settings
        let updater = self.updater
        let instance = self.instance
        sessions.armAlarm(
            id, schedule: settings.isEnabled ? settings.schedule : nil, label: settings.label, sound: settings.sound
        ) {
            updater.set(AlarmSettings.enabled.name, to: "false", in: instance)
        }
    }
}

enum AlarmText {
    /// "Ringing", the label, "Tomorrow" (when it next rings), or "Off".
    static func caption(_ settings: AlarmSettings, ringing: Bool, next: Date?, now: Date) -> String {
        if ringing { return "Ringing" }
        guard settings.isEnabled else { return settings.label.isEmpty ? "Off" : "\(settings.label) · Off" }
        if !settings.label.isEmpty { return settings.label }
        if let next { return TimerFormatting.dayLabel(for: next, now: now) }
        return settings.repeats.title
    }

    /// "Rings tomorrow at 7:00 AM", or what Snooze set.
    static func nextLine(_ settings: AlarmSettings, next: Date?, now: Date) -> String {
        guard settings.isEnabled else { return "Off" }
        guard let next else { return "Not scheduled" }
        let day = TimerFormatting.dayLabel(for: next, now: now)
        let time = next.formatted(date: .omitted, time: .shortened)
        let when = day == "Today" || day == "Tomorrow" ? day.lowercased() : "on \(day)"
        return "Rings \(when) at \(time)"
    }
}

/// Shown when the tile is clicked: the on/off switch, the time and repeat, and Snooze and
/// Stop while it rings.
struct AlarmPopoutView: View {
    let instance: WidgetInstance

    @Environment(\.widgetUpdateSettings) private var updater
    @State private var sessions = TimerSessions.shared

    private var settings: AlarmSettings { AlarmSettings(instance: instance) }
    private var id: UUID { updater.id }

    var body: some View {
        let settings = self.settings
        let ringing = sessions.isRinging(id)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(settings.label.isEmpty ? "Alarm" : settings.label).font(.headline)
                Spacer()
                Toggle("On", isOn: enabledBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("Alarm on")
            }

            if ringing {
                HStack(spacing: 10) {
                    Button("Snooze \(settings.snoozeMinutes) min") {
                        sessions.snoozeAlarm(id, minutes: settings.snoozeMinutes)
                    }
                    Button("Stop") { sessions.stopAlarm(id) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Text(AlarmText.nextLine(settings, next: sessions.armedAlarms[id], now: .now))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
            Picker("Repeat", selection: repeatsBinding) {
                ForEach(AlarmRepeat.allCases, id: \.rawValue) { repeats in
                    Text(repeats.title).tag(repeats.rawValue)
                }
            }
        }
        .padding(16)
        .frame(width: 264, alignment: .leading)
    }

    // The popout is rebuilt with each change, so its bindings write straight to the store.

    private var repeatsBinding: Binding<String> {
        Binding(
            get: { settings.repeats.rawValue },
            set: { updater.set(AlarmSettings.repeats.name, to: $0, in: instance) }
        )
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { updater.set(AlarmSettings.enabled.name, to: $0 ? "true" : "false", in: instance) }
        )
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { settings.time.date(on: .now, calendar: .current) ?? .now },
            set: {
                updater.set(
                    AlarmSettings.time.name, to: AlarmTime(of: $0, calendar: .current).storageValue, in: instance)
            }
        )
    }
}

/// Settings for one alarm tile: everything the popover has, plus the label, snooze and sound.
struct AlarmSettingsView: View {
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var instance: WidgetInstance

    init(instance: WidgetInstance) {
        _instance = State(initialValue: instance)
    }

    private var settings: AlarmSettings { AlarmSettings(instance: instance) }

    var body: some View {
        Form {
            Toggle("Alarm on", isOn: updater.boolBinding(AlarmSettings.enabled, in: $instance))
            DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
            Picker("Repeat", selection: updater.stringBinding(AlarmSettings.repeats, in: $instance)) {
                ForEach(AlarmRepeat.allCases, id: \.rawValue) { repeats in
                    Text(repeats.title).tag(repeats.rawValue)
                }
            }
            WidgetTextSetting("Label", key: AlarmSettings.label, instance: $instance, prompt: Text("Name"))
            Stepper(
                "Snooze: \(settings.snoozeMinutes) min",
                value: updater.intBinding(AlarmSettings.snoozeMinutes, in: $instance), in: 1 ... 60)
            Toggle("Play a sound while ringing", isOn: updater.boolBinding(AlarmSettings.sound, in: $instance))
            WidgetCaption(
                "The alarm rings while its tile is in the dock and OpenDock is running, and shows a notification; "
                    + "macOS asks once to allow those."
            )
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { settings.time.date(on: .now, calendar: .current) ?? .now },
            set: { newValue in
                instance.settings[AlarmSettings.time.name] = AlarmTime(of: newValue, calendar: .current).storageValue
                updater(instance)
            }
        )
    }
}
