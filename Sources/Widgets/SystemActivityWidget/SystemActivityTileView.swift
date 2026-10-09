import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// The in-dock tile: one gauge per enabled metric. CPU is drawn as a percentage over a
/// sparkline of the last minute when `showCPUHistory` is on, otherwise as a ring like
/// memory and disk.
struct SystemActivityTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockIsVisible) private var isVisible
    @Environment(\.dockEdge) private var edge
    @State private var monitor = SystemActivityMonitor.shared

    private var metrics: [SystemActivityMetric] { SystemActivitySettings.metrics(in: instance) }
    private var showsHistory: Bool { SystemActivitySettings.showCPUHistory.boolValue(in: instance.settings) }

    var body: some View {
        WidgetTile {
            // Gauges side by side along the bottom edge, one above the other on a side edge.
            WidgetStack(spacing: iconSize * (edge.isVertical ? 0.1 : 0.16)) {
                ForEach(metrics) { metric in
                    switch metric {
                    case .cpu where showsHistory: cpuHistory
                    case .cpu: ring(for: .cpu, progress: snapshot.cpu?.total, color: cpuColor)
                    case .memory: ring(for: .memory, progress: snapshot.memory?.usedFraction, color: memoryColor)
                    case .disk: ring(for: .disk, progress: snapshot.disk?.usedFraction, color: diskColor)
                    }
                }
            }
        }
        // The task dies with the dock, so a hidden dock samples nothing.
        .task(id: isVisible) {
            if isVisible { await monitor.autoRefresh() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var snapshot: SystemActivitySnapshot { monitor.snapshot }
    private var cpuColor: Color { SystemActivityStyle.cpuColor(snapshot.cpu) }
    private var memoryColor: Color {
        SystemActivityStyle.memoryColor(snapshot.memory, pressure: snapshot.memoryPressure)
    }
    private var diskColor: Color { SystemActivityStyle.diskColor(snapshot.disk) }

    // MARK: Gauges

    private func ring(for metric: SystemActivityMetric, progress: Double?, color: Color) -> some View {
        let size = iconSize * 0.62
        return WidgetRing(fraction: progress ?? 0, color: color, lineWidth: max(2.5, iconSize * 0.07))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: metric.systemImage)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(progress == nil ? Color.secondary : color)
            }
            .help(helpText(for: metric, progress: progress))
    }

    private var cpuHistory: some View {
        VStack(alignment: edge.isVertical ? .center : .leading, spacing: iconSize * 0.04) {
            HStack(spacing: iconSize * 0.08) {
                Image(systemName: SystemActivityMetric.cpu.systemImage)
                    .font(.system(size: WidgetMetrics.secondaryFontSize(for: iconSize), weight: .semibold))
                    .foregroundStyle(.secondary)
                WidgetPrimaryText(snapshot.cpu.map { SystemActivityFormatting.percent($0.total) } ?? "—%")
            }
            // On a side edge the sparkline fits the icon-wide tile.
            Sparkline(samples: monitor.history.samples, capacity: monitor.history.capacity, color: cpuColor)
                .frame(width: iconSize * (edge.isVertical ? 0.8 : 1.1), height: iconSize * 0.3)
        }
        .help(helpText(for: .cpu, progress: snapshot.cpu?.total))
    }

    private func helpText(for metric: SystemActivityMetric, progress: Double?) -> String {
        guard let progress else { return "\(metric.title): reading…" }
        return "\(metric.title): \(SystemActivityFormatting.percent(progress))"
    }

    private var accessibilityLabel: String {
        let parts = metrics.map { metric -> String in
            let value: Double? =
                switch metric {
                case .cpu: snapshot.cpu?.total
                case .memory: snapshot.memory?.usedFraction
                case .disk: snapshot.disk?.usedFraction
                }
            guard let value else { return "\(metric.title) unknown" }
            return "\(metric.title) \(Int((value * 100).rounded())) percent"
        }
        return "System activity: " + parts.joined(separator: ", ")
    }
}
