import DockCore
import DockWidgetKit
import SwiftUI

/// The in-dock stopwatch tile: elapsed time, the latest lap, and start/stop and lap buttons.
struct StopwatchTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var sessions = TimerSessions.shared

    private var settings: StopwatchSettings { StopwatchSettings(instance: instance) }
    private var id: UUID { updater.id }

    var body: some View {
        let stopwatch = sessions.stopwatch(for: id)
        WidgetTicking(interval: 1, active: stopwatch.isRunning) { now in
            WidgetTile {
                WidgetStack(spacing: iconSize * (edge.isVertical ? 0.08 : 0.16)) {
                    VStack(alignment: edge.isVertical ? .center : .leading, spacing: 0) {
                        WidgetPrimaryText(TimerFormatting.stopwatch(stopwatch.elapsed(at: now), tenths: false))
                        WidgetSecondaryText(caption(stopwatch))
                    }
                    HStack(spacing: iconSize * (edge.isVertical ? 0.04 : 0.1)) {
                        TimerButton(
                            symbol: stopwatch.isRunning ? "pause.fill" : "play.fill", size: iconSize * 0.3,
                            label: stopwatch.isRunning ? "Stop" : "Start", compact: edge.isVertical
                        ) {
                            sessions.toggleStopwatch(id)
                        }
                        if stopwatch.isRunning {
                            TimerButton(
                                symbol: "flag.fill", size: iconSize * 0.26, label: "Lap", compact: edge.isVertical
                            ) {
                                sessions.lapStopwatch(id)
                            }
                        } else if stopwatch.hasStarted {
                            TimerButton(
                                symbol: "arrow.counterclockwise", size: iconSize * 0.26, label: "Reset",
                                compact: edge.isVertical
                            ) {
                                sessions.resetStopwatch(id)
                            }
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                "Stopwatch \(stopwatch.isRunning ? "running" : "stopped"), "
                    + TimerFormatting.stopwatch(stopwatch.elapsed(at: now), tenths: false))
        }
    }

    /// "Lap 3 · 00:42" when laps are shown and there is one, else the widget's name.
    private func caption(_ stopwatch: Stopwatch) -> String {
        if settings.showLaps, let lap = stopwatch.laps.last {
            return "Lap \(lap.number) · \(TimerFormatting.stopwatch(lap.duration, tenths: false))"
        }
        return "Stopwatch"
    }
}

/// Shown when the tile is clicked: the time to a tenth of a second, the buttons, and the laps
/// with their splits, newest first.
struct StopwatchPopoutView: View {
    let instance: WidgetInstance

    @Environment(\.widgetUpdateSettings) private var updater
    @State private var sessions = TimerSessions.shared

    private var id: UUID { updater.id }

    var body: some View {
        let stopwatch = sessions.stopwatch(for: id)
        WidgetTicking(interval: 0.1, active: stopwatch.isRunning) { now in
            VStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text(TimerFormatting.stopwatch(stopwatch.elapsed(at: now), tenths: true))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if !stopwatch.laps.isEmpty {
                        Text(
                            "Lap \(stopwatch.laps.count + 1) · "
                                + TimerFormatting.stopwatch(stopwatch.currentLap(at: now), tenths: true)
                        )
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button(stopwatch.isRunning ? "Lap" : "Reset") {
                        if stopwatch.isRunning { sessions.lapStopwatch(id) } else { sessions.resetStopwatch(id) }
                    }
                    .disabled(!stopwatch.hasStarted)
                    Button(stopwatch.isRunning ? "Stop" : "Start") { sessions.toggleStopwatch(id) }
                        .buttonStyle(.borderedProminent)
                        .tint(stopwatch.isRunning ? .red : .green)
                        .keyboardShortcut(.defaultAction)
                }

                if !stopwatch.laps.isEmpty {
                    Divider()
                    laps(stopwatch)
                }
            }
        }
        .padding(16)
        .frame(width: 264)
    }

    private func laps(_ stopwatch: Stopwatch) -> some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(stopwatch.laps.reversed()) { lap in
                    HStack {
                        Text("Lap \(lap.number)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(TimerFormatting.stopwatch(lap.duration, tenths: true))
                            .monospacedDigit()
                            .foregroundStyle(lapColor(lap, in: stopwatch))
                        Text(TimerFormatting.stopwatch(lap.total, tenths: true))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 76, alignment: .trailing)
                    }
                    .font(.callout)
                }
            }
        }
        .frame(maxHeight: 160)
    }

    /// The fastest lap in green and the slowest in red, once there are two to compare.
    private func lapColor(_ lap: Stopwatch.Lap, in stopwatch: Stopwatch) -> Color {
        if lap == stopwatch.fastestLap { return .green }
        if lap == stopwatch.slowestLap { return .red }
        return .primary
    }
}

/// Settings for one stopwatch tile.
struct StopwatchSettingsView: View {
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var instance: WidgetInstance

    init(instance: WidgetInstance) {
        _instance = State(initialValue: instance)
    }

    var body: some View {
        Form {
            Toggle("Show the latest lap", isOn: updater.boolBinding(StopwatchSettings.showLaps, in: $instance))
            Text("Start, stop and lap from the tile; click it for tenths of a second and every lap.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
