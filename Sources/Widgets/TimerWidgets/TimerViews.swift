import DockCore
import DockWidgetKit
import SwiftUI

// Pieces the four time widgets share: a ring, a tile button, a ticking container, and a
// binding for integer settings.

/// Redraws its content every `interval` seconds while `active` and the dock is on screen,
/// on ticks aligned to whole intervals so a clock's digits change on the second. Otherwise
/// it redraws about once an hour and catches up as soon as it's needed again.
struct TimerTicking<Content: View>: View {
    let interval: TimeInterval
    let active: Bool
    @ViewBuilder let content: (Date) -> Content

    @Environment(\.dockIsVisible) private var isVisible

    var body: some View {
        let period = active && isVisible ? interval : 3600
        let start = Date(
            timeIntervalSinceReferenceDate: (Date.now.timeIntervalSinceReferenceDate / period).rounded(.down) * period)
        TimelineView(.periodic(from: start, by: period)) { context in
            content(context.date)
        }
    }
}

/// A ring that empties as time runs out: a faint track plus a colored arc from 12 o'clock
/// covering `fraction` of the circle. Moves smoothly between one-second ticks.
struct TimerRing: View {
    let fraction: Double
    let color: Color
    let lineWidth: Double

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .animation(.linear(duration: 1), value: fraction)
    }
}

/// A symbol button for a tile, sized from the icon size. `compact` tightens the hit area for
/// a tile that is only an icon wide (on a side edge).
struct TimerButton: View {
    let symbol: String
    let size: Double
    let label: String
    var compact = false
    let action: () -> Void

    var body: some View {
        let hitSize = size * (compact ? 1.3 : 1.6)
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .frame(width: hitSize, height: hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help(label)
        .accessibilityLabel(label)
    }
}

extension WidgetSettingsUpdater {
    /// A binding for an `.integer` key, for steppers. Reads through the key, so an invalid
    /// stored value shows as the default.
    func intBinding(_ key: WidgetSettingKey, in instance: Binding<WidgetInstance>) -> Binding<Int> {
        Binding(
            get: { key.intValue(in: instance.wrappedValue.settings) },
            set: { newValue in
                instance.wrappedValue.settings[key.name] = String(newValue)
                self(instance.wrappedValue)
            }
        )
    }
}

enum TimerStyle {
    /// Focus sessions are warm, breaks are green.
    static func color(for phase: FocusTimer.Phase) -> Color {
        phase.isBreak ? .green : .orange
    }

    /// A time of day in the user's clock format: "7:00 AM" or "07:00".
    static func timeOfDay(_ time: AlarmTime, on day: Date = .now) -> String {
        time.date(on: day, calendar: .current)?.formatted(date: .omitted, time: .shortened) ?? time.storageValue
    }
}
