import DockCore
import DockWidgetKit
import SwiftUI

/// The in-dock countdown tile: an hourglass, the time left, and the label or the date.
struct CountdownTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var sessions = TimerSessions.shared

    private var settings: CountdownSettings { CountdownSettings(instance: instance) }
    private var id: UUID { updater.id }

    var body: some View {
        let settings = self.settings
        let target = settings.target
        TimerTicking(interval: 1, active: target != nil) { now in
            let remaining = target.map { CountdownTarget.remaining(until: $0, from: now) }
            WidgetTile {
                WidgetStack(spacing: iconSize * (edge.isVertical ? 0.06 : 0.14)) {
                    Image(systemName: "hourglass")
                        .font(.system(size: iconSize * 0.36, weight: .semibold))
                        .foregroundStyle(hourglassStyle(remaining))
                    VStack(alignment: edge.isVertical ? .center : .leading, spacing: 0) {
                        if let remaining, let target {
                            WidgetPrimaryText(TimerFormatting.compactCountdown(remaining))
                            WidgetSecondaryText(CountdownText.caption(label: settings.label, target: target))
                        } else {
                            WidgetPrimaryText("Countdown")
                            WidgetSecondaryText("Set a date")
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(remaining, target: target))
        }
        .onAppear(perform: arm)
        .onChange(of: instance.settings) { arm() }
        .onDisappear { sessions.removeCountdown(id) }
    }

    private func arm() {
        sessions.armCountdown(id, target: settings.notify ? settings.target : nil, label: settings.label)
    }

    /// Tinted while counting; grey when unset or over.
    private func hourglassStyle(_ remaining: CountdownTarget.Remaining?) -> AnyShapeStyle {
        guard let remaining, !remaining.isPast else { return AnyShapeStyle(HierarchicalShapeStyle.secondary) }
        return AnyShapeStyle(TintShapeStyle())
    }

    private func accessibilityLabel(_ remaining: CountdownTarget.Remaining?, target: Date?) -> String {
        guard let remaining, let target else { return "Countdown: no date set" }
        let name = settings.label.isEmpty ? "Countdown" : settings.label
        return "\(name): \(TimerFormatting.longCountdown(remaining)) until \(CountdownText.dateLine(target))"
    }
}

enum CountdownText {
    /// The label when there is one, else the date as "Dec 25".
    static func caption(label: String, target: Date) -> String {
        label.isEmpty ? target.formatted(.dateTime.month(.abbreviated).day()) : label
    }

    /// "Thursday, December 25, 2026 at 6:00 PM"
    static func dateLine(_ target: Date) -> String {
        target.formatted(date: .complete, time: .shortened)
    }

    /// The next whole hour, to start a new countdown from.
    static func suggestedTarget(after now: Date = .now) -> Date {
        Calendar.current.nextDate(
            after: now, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) ?? now
    }
}

/// Shown when the tile is clicked: the time left in words, the date, and a picker to change it.
struct CountdownPopoutView: View {
    let instance: WidgetInstance

    @Environment(\.widgetUpdateSettings) private var updater

    private var settings: CountdownSettings { CountdownSettings(instance: instance) }

    var body: some View {
        let settings = self.settings
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.label.isEmpty ? "Countdown" : settings.label).font(.headline)

            if let target = settings.target {
                TimerTicking(interval: 1, active: true) { now in
                    let remaining = CountdownTarget.remaining(until: target, from: now)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TimerFormatting.longCountdown(remaining))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                        Text(
                            remaining.isPast ? "Was \(CountdownText.dateLine(target))" : CountdownText.dateLine(target)
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Pick a date and time to count down to.")
                    .foregroundStyle(.secondary)
            }

            Divider()

            DatePicker("Counting down to", selection: dateBinding, displayedComponents: [.date, .hourAndMinute])
        }
        .padding(16)
        .frame(width: 290, alignment: .leading)
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { settings.target ?? CountdownText.suggestedTarget() },
            set: { updater.set(CountdownSettings.date.name, to: CountdownTarget.storageValue(for: $0), in: instance) }
        )
    }
}

/// Settings for one countdown tile: the date, its label, and the notification.
struct CountdownSettingsView: View {
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var instance: WidgetInstance
    @State private var label: String

    init(instance: WidgetInstance) {
        _instance = State(initialValue: instance)
        _label = State(initialValue: CountdownSettings.label.value(in: instance.settings))
    }

    private var settings: CountdownSettings { CountdownSettings(instance: instance) }

    var body: some View {
        Form {
            DatePicker("Counting down to", selection: dateBinding, displayedComponents: [.date, .hourAndMinute])
            if settings.target != nil {
                Button("Clear Date") {
                    instance.settings[CountdownSettings.date.name] = ""
                    updater(instance)
                }
            }

            TextField("Label", text: $label, prompt: Text("What it's for"))
                .onSubmit(commitLabel)

            Toggle("Notify when it reaches zero", isOn: updater.boolBinding(CountdownSettings.notify, in: $instance))
        }
        .onDisappear(perform: commitLabel)
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { settings.target ?? CountdownText.suggestedTarget() },
            set: { newValue in
                instance.settings[CountdownSettings.date.name] = CountdownTarget.storageValue(for: newValue)
                updater(instance)
            }
        )
    }

    /// Committed on submit and when the view goes away, not on every keystroke.
    private func commitLabel() {
        guard label != CountdownSettings.label.value(in: instance.settings) else { return }
        instance.settings[CountdownSettings.label.name] = label
        updater(instance)
    }
}
