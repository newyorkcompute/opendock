import DockCore
import DockWidgetKit
import SwiftUI

/// Detail view shown when the tile is clicked: every period, whichever ones the tile shows,
/// with a precise percentage, a bar, and how far along and how much is left.
struct TimeProgressPopoutView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time Progress").font(.headline)
                    Text(context.date.formatted(Date.FormatStyle(locale: locale).weekday(.wide).month(.wide).day()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(TimeProgressPeriod.allCases, id: \.self) { period in
                    if let progress = TimeProgress(of: period, at: context.date, calendar: calendar) {
                        PeriodRow(progress: progress, locale: locale)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
    }
}

private struct PeriodRow: View {
    let progress: TimeProgress
    let locale: Locale

    private var color: Color { TimeProgressStyle.color(for: progress.period) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(TimeProgressStyle.title(for: progress.period))
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Text(progress.percentText(fractionDigits: 1))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
            TimeProgressBar(fraction: progress.fraction, color: color)
                .frame(height: 6)
            HStack {
                Text(position)
                Spacer(minLength: 8)
                Text(progress.remainingText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    /// "Day 9 of 31" for the longer periods; the time of day for the day itself.
    private var position: String {
        switch progress.period {
        case .day:
            progress.date.formatted(Date.FormatStyle(locale: locale).hour().minute())
        case .week, .month, .year:
            "Day \(progress.dayOrdinal) of \(progress.dayCount)"
        }
    }
}
