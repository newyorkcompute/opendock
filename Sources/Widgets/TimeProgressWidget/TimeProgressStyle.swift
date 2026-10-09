import DockCore
import SwiftUI

/// Names, colors, and small shapes shared by the tile and the popover.
enum TimeProgressStyle {
    /// "Year", "Month", "Week", "Day".
    static func title(for period: TimeProgressPeriod) -> String {
        switch period {
        case .year: "Year"
        case .month: "Month"
        case .week: "Week"
        case .day: "Day"
        }
    }

    /// One letter for where a word won't fit.
    static func letter(for period: TimeProgressPeriod) -> String {
        String(title(for: period).prefix(1))
    }

    /// Each period keeps its color across styles, so the eye finds it without reading.
    static func color(for period: TimeProgressPeriod) -> Color {
        switch period {
        case .year: .indigo
        case .month: .blue
        case .week: .teal
        case .day: .orange
        }
    }
}

/// A horizontal progress bar: faint track with a colored fill from the left. A fill that
/// would be thinner than it is tall shows as a dot, so a period that has barely begun still
/// reads as started.
struct TimeProgressBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let clamped = max(0, min(1, fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.22))
                if clamped > 0 {
                    Capsule().fill(color)
                        .frame(width: max(proxy.size.height, proxy.size.width * clamped))
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}
