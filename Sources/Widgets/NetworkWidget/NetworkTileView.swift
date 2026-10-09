import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// The in-dock tile: the download and upload speeds, one above the other, with a
/// sparkline of the last minute beside them when `showHistory` is on.
struct NetworkTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockIsVisible) private var isVisible
    @Environment(\.dockEdge) private var edge
    @State private var monitor = NetworkActivityMonitor.shared

    private var directions: [NetworkDirection] { NetworkSettings.directions(in: instance) }
    private var showsHistory: Bool { NetworkSettings.showHistory.boolValue(in: instance.settings) }
    private var unit: NetworkRateUnit { NetworkSettings.unit(in: instance) }
    private var selection: NetworkInterfaceSelection { NetworkSettings.selection(in: instance) }

    private var snapshot: NetworkActivitySnapshot { monitor.snapshot }
    private var throughput: NetworkThroughput? { snapshot.throughput(for: selection) }

    var body: some View {
        WidgetTile(minWidth: minWidth) {
            // Speeds beside the sparkline along the bottom edge, above it on a side edge.
            WidgetStack(spacing: iconSize * (edge.isVertical ? 0.08 : 0.16)) {
                speeds
                if showsHistory {
                    sparkline
                }
            }
        }
        // The task dies with the dock, so a hidden dock samples nothing.
        .task(id: isVisible) {
            if isVisible { await monitor.autoRefresh() }
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Wide enough for "999 KB/s" so the tile doesn't jitter as the digits change.
    private var minWidth: Double {
        let text = directions.count == 1 ? 1.6 : 1.4
        return iconSize * (text + (showsHistory ? 1.2 : 0))
    }

    // MARK: Speeds

    @ViewBuilder
    private var speeds: some View {
        if directions.count == 1, let direction = directions.first {
            speed(direction, size: WidgetMetrics.primaryFontSize(for: iconSize))
        } else {
            VStack(alignment: .leading, spacing: iconSize * 0.04) {
                ForEach(directions) { direction in
                    speed(direction, size: WidgetMetrics.secondaryFontSize(for: iconSize) * 1.15)
                }
            }
        }
    }

    private func speed(_ direction: NetworkDirection, size: Double) -> some View {
        HStack(spacing: size * 0.3) {
            Image(systemName: direction.systemImage)
                .font(.system(size: size * 0.8, weight: .bold))
                .foregroundStyle(throughput == nil ? Color.secondary : NetworkStyle.color(for: direction))
            Text(rateText(for: direction))
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private func rateText(for direction: NetworkDirection) -> String {
        guard let throughput else { return "—" }
        return NetworkFormatting.rate(direction.bytesPerSecond(in: throughput), unit: unit)
    }

    // MARK: History

    private var sparkline: some View {
        let readings = snapshot.interfaces.map(\.reading)
        let series = monitor.history.series(for: selection, interfaces: readings)
        // On a side edge the sparkline fits the icon-wide tile.
        return NetworkSparkline(download: series.download, upload: series.upload, capacity: monitor.history.capacity)
            .frame(width: iconSize * (edge.isVertical ? 0.8 : 1.1), height: iconSize * (edge.isVertical ? 0.4 : 0.55))
    }

    // MARK: Text

    private var helpText: String {
        if snapshot.isMissing(selection) {
            return "\(selection.settingValue) isn't connected"
        }
        guard let throughput else { return "Network: reading…" }
        return NetworkDirection.allCases.map {
            "\($0.title) \(NetworkFormatting.rate($0.bytesPerSecond(in: throughput), unit: unit))"
        }.joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        guard let throughput else { return "Network: no reading yet" }
        let parts = directions.map {
            "\($0.title.lowercased()) \(NetworkFormatting.rate($0.bytesPerSecond(in: throughput), unit: unit))"
        }
        return "Network: " + parts.joined(separator: ", ")
    }
}
