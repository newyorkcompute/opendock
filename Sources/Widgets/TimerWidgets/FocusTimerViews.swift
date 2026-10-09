import DockCore
import DockWidgetKit
import SwiftUI

/// The in-dock focus timer tile: a ring that empties over the session, the time left, which
/// session this is, and a play/pause button.
struct FocusTimerTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var sessions = TimerSessions.shared

    private var settings: FocusTimerSettings { FocusTimerSettings(instance: instance) }
    private var id: UUID { updater.id }

    var body: some View {
        let plan = settings.plan
        let timer = sessions.focusTimer(for: id, plan: plan)
        let color = TimerStyle.color(for: timer.phase)
        WidgetTicking(interval: 1, active: timer.isRunning) { now in
            WidgetTile {
                WidgetStack(spacing: iconSize * (edge.isVertical ? 0.08 : 0.16)) {
                    ring(timer, color: color, at: now)
                    VStack(alignment: edge.isVertical ? .center : .leading, spacing: 0) {
                        WidgetPrimaryText(TimerFormatting.countdown(timer.remaining(at: now)))
                        WidgetSecondaryText(FocusTimerText.caption(for: timer))
                    }
                    TimerButton(
                        symbol: timer.isRunning ? "pause.fill" : "play.fill", size: iconSize * 0.3,
                        label: timer.isRunning ? "Pause" : "Start", compact: edge.isVertical
                    ) {
                        sessions.toggleFocus(id, plan: plan)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                "\(FocusTimerText.caption(for: timer)), \(TimerFormatting.countdown(timer.remaining(at: now))) left")
        }
        .onAppear(perform: sync)
        .onChange(of: instance.settings) { sync() }
    }

    private func ring(_ timer: FocusTimer, color: Color, at now: Date) -> some View {
        let ringSize = iconSize * 0.6
        return WidgetRing(
            fraction: timer.fractionRemaining(at: now), color: color, lineWidth: max(2.5, iconSize * 0.07),
            animation: .linear(duration: 1)
        )
        .frame(width: ringSize, height: ringSize)
        .overlay {
            Image(systemName: timer.phase.isBreak ? "cup.and.saucer.fill" : "timer")
                .font(.system(size: ringSize * 0.38, weight: .bold))
                .foregroundStyle(color)
        }
        .opacity(timer.isIdle ? 0.7 : 1)
    }

    /// Hand the settings' durations to the shared timer.
    private func sync() {
        sessions.updateFocus(id, plan: settings.plan, options: settings.options)
    }
}

/// Words for the tile and popover.
enum FocusTimerText {
    /// "Focus 2 of 4", "Break", "Long break", or "Paused".
    static func caption(for timer: FocusTimer) -> String {
        if timer.isPaused { return "Paused" }
        return phase(of: timer)
    }

    static func phase(of timer: FocusTimer) -> String {
        switch timer.phase {
        case .focus where timer.plan.sessionsBeforeLongBreak > 1:
            "Focus \(timer.sessionNumber) of \(timer.plan.sessionsBeforeLongBreak)"
        default:
            timer.phase.title
        }
    }

    /// "25 min focus · 5 min break · 15 min long break after 4"
    static func planSummary(_ plan: FocusTimer.Plan) -> String {
        let focus = TimerFormatting.minutes(Int(plan.focus / 60))
        let short = TimerFormatting.minutes(Int(plan.shortBreak / 60))
        let long = TimerFormatting.minutes(Int(plan.longBreak / 60))
        return "\(focus) focus · \(short) break · \(long) long break after \(plan.sessionsBeforeLongBreak)"
    }
}

/// Shown when the tile is clicked: a bigger ring with Start, Pause, Skip and Reset, and dots
/// for the sessions of the current cycle.
struct FocusTimerPopoutView: View {
    let instance: WidgetInstance

    @Environment(\.widgetUpdateSettings) private var updater
    @State private var sessions = TimerSessions.shared

    private var settings: FocusTimerSettings { FocusTimerSettings(instance: instance) }
    private var id: UUID { updater.id }

    var body: some View {
        let plan = settings.plan
        let timer = sessions.focusTimer(for: id, plan: plan)
        let color = TimerStyle.color(for: timer.phase)
        WidgetTicking(interval: 1, active: timer.isRunning) { now in
            VStack(spacing: 14) {
                HStack {
                    Text("Focus Timer").font(.headline)
                    Spacer()
                    sessionDots(timer, color: color)
                }

                WidgetRing(
                    fraction: timer.fractionRemaining(at: now), color: color, lineWidth: 8,
                    animation: .linear(duration: 1)
                )
                .frame(width: 128, height: 128)
                .overlay {
                    VStack(spacing: 2) {
                        Text(TimerFormatting.countdown(timer.remaining(at: now)))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(FocusTimerText.caption(for: timer))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button("Reset") { sessions.resetFocus(id, plan: plan) }
                        .help(timer.isIdle ? "Back to the first session" : "Back to the start of this phase")
                    Button(timer.isRunning ? "Pause" : "Start") { sessions.toggleFocus(id, plan: plan) }
                        .buttonStyle(.borderedProminent)
                        .tint(color)
                        .keyboardShortcut(.defaultAction)
                    Button("Skip") { sessions.skipFocus(id, plan: plan) }
                        .help("End this phase now")
                }

                Text(FocusTimerText.planSummary(plan))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .frame(width: 264)
        .onAppear { sessions.updateFocus(id, plan: settings.plan, options: settings.options) }
    }

    /// One dot per session in the cycle, filled for the ones done.
    private func sessionDots(_ timer: FocusTimer, color: Color) -> some View {
        let count = timer.plan.sessionsBeforeLongBreak
        let done = timer.phase == .longBreak ? count : timer.completedSessions % count
        return HStack(spacing: 4) {
            ForEach(0 ..< count, id: \.self) { index in
                Circle()
                    .fill(index < done ? color : color.opacity(0.25))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("\(done) of \(count) sessions done")
    }
}

/// Settings for one focus timer tile: the durations and what happens when a phase ends.
struct FocusTimerSettingsView: View {
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var instance: WidgetInstance

    init(instance: WidgetInstance) {
        _instance = State(initialValue: instance)
    }

    var body: some View {
        let plan = FocusTimerSettings(instance: instance).plan
        Form {
            Stepper(
                "Focus: \(TimerFormatting.minutes(Int(plan.focus / 60)))",
                value: updater.intBinding(FocusTimerSettings.focusMinutes, in: $instance), in: 1 ... 180, step: 5)
            Stepper(
                "Break: \(TimerFormatting.minutes(Int(plan.shortBreak / 60)))",
                value: updater.intBinding(FocusTimerSettings.shortBreakMinutes, in: $instance), in: 1 ... 60)
            Stepper(
                "Long break: \(TimerFormatting.minutes(Int(plan.longBreak / 60)))",
                value: updater.intBinding(FocusTimerSettings.longBreakMinutes, in: $instance), in: 1 ... 120, step: 5)
            Stepper(
                "Sessions per cycle: \(plan.sessionsBeforeLongBreak)",
                value: updater.intBinding(FocusTimerSettings.sessionsBeforeLongBreak, in: $instance), in: 1 ... 12)

            Toggle(
                "Start the next session or break automatically",
                isOn: updater.boolBinding(FocusTimerSettings.autoStart, in: $instance))
            Toggle(
                "Notify when a session or break ends",
                isOn: updater.boolBinding(FocusTimerSettings.notify, in: $instance))
            Text("Notifications show as banners; macOS asks once to allow them. The timer stops when OpenDock quits.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
