import DockCore
import DockWidgetKit
import SwiftUI

/// The in-dock time progress tile. One period gets a large percentage with its bar or ring
/// and what's left; several share the tile as labeled rows of bars, or a row of rings.
struct TimeProgressTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockIsVisible) private var isVisible
    @Environment(\.dockEdge) private var edge
    @Environment(\.calendar) private var calendar

    var body: some View {
        let settings = TimeProgressSettings(instance: instance)
        if isVisible {
            // The day moves about 0.07% a minute, so a tick a minute is plenty. Off screen, the
            // tile keeps whatever it last drew and catches up when the dock comes back.
            let minute: TimeInterval = 60
            let start = Date(
                timeIntervalSinceReferenceDate: (Date.now.timeIntervalSinceReferenceDate / minute).rounded(.down)
                    * minute)
            TimelineView(.periodic(from: start, by: minute)) { context in
                tile(at: context.date, settings: settings)
            }
        } else {
            tile(at: .now, settings: settings)
        }
    }

    private func tile(at date: Date, settings: TimeProgressSettings) -> some View {
        let progress = settings.periods.compactMap { TimeProgress(of: $0, at: date, calendar: calendar) }
        return WidgetTile {
            if progress.count == 1, let single = progress.first, !edge.isVertical {
                switch settings.style {
                case .bars: barHero(single)
                case .rings: ringHero(single)
                }
            } else {
                switch settings.style {
                case .bars:
                    if edge.isVertical {
                        stackedBars(progress)
                    } else {
                        barRows(progress)
                    }
                case .rings:
                    ringRow(progress)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(progress))
    }

    // MARK: One period

    /// "72%  Month · 22 days left" over a wide bar.
    private func barHero(_ progress: TimeProgress) -> some View {
        VStack(alignment: .leading, spacing: iconSize * 0.07) {
            HStack(alignment: .firstTextBaseline, spacing: iconSize * 0.12) {
                WidgetPrimaryText("\(progress.percent)%")
                WidgetSecondaryText(caption(progress))
            }
            TimeProgressBar(fraction: progress.fraction, color: TimeProgressStyle.color(for: progress.period))
                .frame(height: max(3, iconSize * 0.08))
        }
        .frame(width: iconSize * 2.9, alignment: .leading)
    }

    /// A ring with the period's letter, then the percentage and caption beside it.
    private func ringHero(_ progress: TimeProgress) -> some View {
        let color = TimeProgressStyle.color(for: progress.period)
        let ringSize = iconSize * 0.6
        return HStack(spacing: iconSize * 0.16) {
            TimeProgressRing(fraction: progress.fraction, color: color, lineWidth: max(2.5, iconSize * 0.07))
                .frame(width: ringSize, height: ringSize)
                .overlay {
                    Text(TimeProgressStyle.letter(for: progress.period))
                        .font(.system(size: ringSize * 0.4, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                }
            VStack(alignment: .leading, spacing: 0) {
                WidgetPrimaryText("\(progress.percent)%")
                WidgetSecondaryText(caption(progress))
            }
        }
    }

    private func caption(_ progress: TimeProgress) -> String {
        "\(TimeProgressStyle.title(for: progress.period)) · \(progress.remainingText)"
    }

    // MARK: Several periods

    /// Labeled rows along the bottom edge: "Year ████░░ 77%". Four periods go in two columns
    /// with one-letter labels, so no row gets too thin to read.
    private func barRows(_ progress: [TimeProgress]) -> some View {
        let columns = progress.count >= 4 ? 2 : 1
        let rowsPerColumn = max(1, Int((Double(progress.count) / Double(columns)).rounded(.up)))
        let fontSize = min(
            WidgetMetrics.secondaryFontSize(for: iconSize), iconSize * 0.8 / Double(rowsPerColumn) * 0.75)
        let labelWidth = columns == 1 ? fontSize * 3.2 : fontSize * 0.9
        let barWidth = iconSize * (columns == 1 ? 1.0 : 0.7)
        let columnContents = stride(from: 0, to: progress.count, by: rowsPerColumn).map {
            Array(progress[$0 ..< min($0 + rowsPerColumn, progress.count)])
        }

        return HStack(spacing: iconSize * 0.2) {
            ForEach(columnContents, id: \.first?.period) { column in
                VStack(alignment: .leading, spacing: iconSize * 0.05) {
                    ForEach(column, id: \.period) { item in
                        HStack(spacing: fontSize * 0.5) {
                            Text(
                                columns == 1
                                    ? TimeProgressStyle.title(for: item.period)
                                    : TimeProgressStyle.letter(for: item.period)
                            )
                            .font(.system(size: fontSize, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: labelWidth, alignment: .leading)
                            TimeProgressBar(fraction: item.fraction, color: TimeProgressStyle.color(for: item.period))
                                .frame(width: barWidth, height: max(3, fontSize * 0.4))
                            Text("\(item.percent)%")
                                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                                .frame(width: fontSize * 2.1, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    /// On a side edge the tile is an icon wide, so each period is its letter and percentage
    /// over a bar that spans the tile.
    private func stackedBars(_ progress: [TimeProgress]) -> some View {
        let fontSize = WidgetMetrics.secondaryFontSize(for: iconSize) * 0.9
        return VStack(spacing: iconSize * 0.09) {
            ForEach(progress, id: \.period) { item in
                VStack(spacing: iconSize * 0.03) {
                    HStack {
                        Text(TimeProgressStyle.letter(for: item.period))
                            .font(.system(size: fontSize, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 2)
                        Text("\(item.percent)%")
                            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    TimeProgressBar(fraction: item.fraction, color: TimeProgressStyle.color(for: item.period))
                        .frame(height: max(3, iconSize * 0.06))
                }
            }
        }
    }

    /// A ring per period, its letter inside and its percentage underneath. Side by side on
    /// the bottom edge, stacked on a side edge.
    private func ringRow(_ progress: [TimeProgress]) -> some View {
        let ringSize = iconSize * 0.5
        let fontSize = WidgetMetrics.secondaryFontSize(for: iconSize) * 0.9
        return WidgetStack(spacing: iconSize * (edge.isVertical ? 0.14 : 0.12)) {
            ForEach(progress, id: \.period) { item in
                let color = TimeProgressStyle.color(for: item.period)
                VStack(spacing: iconSize * 0.03) {
                    TimeProgressRing(fraction: item.fraction, color: color, lineWidth: max(2, iconSize * 0.055))
                        .frame(width: ringSize, height: ringSize)
                        .overlay {
                            Text(TimeProgressStyle.letter(for: item.period))
                                .font(.system(size: ringSize * 0.42, weight: .bold, design: .rounded))
                                .foregroundStyle(color)
                        }
                    Text("\(item.percent)%")
                        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
    }

    private func accessibilityLabel(_ progress: [TimeProgress]) -> String {
        let parts = progress.map { "\(TimeProgressStyle.title(for: $0.period)) \($0.percent) percent" }
        return "Time progress: " + parts.joined(separator: ", ")
    }
}
