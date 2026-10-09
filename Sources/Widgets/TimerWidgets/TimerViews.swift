import DockCore
import DockWidgetKit
import SwiftUI

// Pieces the four time widgets share: a tile button and some styling.

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
