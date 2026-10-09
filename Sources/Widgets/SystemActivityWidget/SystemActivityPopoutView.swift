import AppKit
import DockWidgetKit
import SwiftUI
import SystemServices

/// Detail view shown when the tile is clicked: overall and per-core CPU, the memory
/// split Activity Monitor uses, swap, and the startup disk.
struct SystemActivityPopoutView: View {
    @State private var monitor = SystemActivityMonitor.shared

    private var snapshot: SystemActivitySnapshot { monitor.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("System Activity").font(.headline)

            cpuSection
            Divider()
            memorySection
            Divider()
            diskSection
            Divider()

            Button("Open Activity Monitor") {
                guard
                    let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor")
                else { return }
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        // The popover is only ever open while the dock is on screen.
        .task { await monitor.autoRefresh() }
    }

    // MARK: CPU

    @ViewBuilder
    private var cpuSection: some View {
        let cpu = snapshot.cpu
        let color = SystemActivityStyle.cpuColor(cpu)
        VStack(alignment: .leading, spacing: 8) {
            MetricHeader(
                title: "CPU",
                systemImage: SystemActivityMetric.cpu.systemImage,
                value: cpu.map { SystemActivityFormatting.percent($0.total) } ?? "—%",
                color: color,
                progress: cpu?.total ?? 0)

            if let cpu {
                let user = SystemActivityFormatting.percent(cpu.user)
                let system = SystemActivityFormatting.percent(cpu.system)
                WidgetCaption("User \(user) · System \(system)")
            } else {
                WidgetCaption("Reading…")
            }

            if !snapshot.cores.isEmpty {
                CoreBars(cores: snapshot.cores)
                    .frame(height: 28)
                WidgetCaption(coresCaption)
            }
        }
    }

    private var coresCaption: String {
        var text = SystemActivityFormatting.coreCount(snapshot.cores.count)
        if !snapshot.loadAverage.isEmpty {
            text += " · Load \(SystemActivityFormatting.loadAverage(snapshot.loadAverage))"
        }
        return text
    }

    // MARK: Memory

    @ViewBuilder
    private var memorySection: some View {
        let memory = snapshot.memory
        let pressure = snapshot.memoryPressure
        let color = SystemActivityStyle.memoryColor(memory, pressure: pressure)
        VStack(alignment: .leading, spacing: 8) {
            MetricHeader(
                title: "Memory",
                systemImage: SystemActivityMetric.memory.systemImage,
                value: memory.map { SystemActivityFormatting.percent($0.usedFraction) } ?? "—%",
                color: color,
                progress: memory?.usedFraction ?? 0)

            if let memory {
                SegmentedBar(segments: [
                    .init(id: 0, fraction: SystemActivityMath.fraction(memory.app, of: memory.total), color: color),
                    .init(
                        id: 1, fraction: SystemActivityMath.fraction(memory.wired, of: memory.total),
                        color: color.opacity(0.7)),
                    .init(
                        id: 2, fraction: SystemActivityMath.fraction(memory.compressed, of: memory.total),
                        color: color.opacity(0.45)),
                ])
                .frame(height: 8)

                let used = SystemActivityFormatting.bytes(memory.used)
                let total = SystemActivityFormatting.bytes(memory.total)
                WidgetCaption("\(used) of \(total) used · Pressure \(pressure.label.lowercased())")

                DetailGrid(rows: [
                    ("App memory", SystemActivityFormatting.bytes(memory.app)),
                    ("Wired", SystemActivityFormatting.bytes(memory.wired)),
                    ("Compressed", SystemActivityFormatting.bytes(memory.compressed)),
                    ("Cached files", SystemActivityFormatting.bytes(memory.cached)),
                    ("Swap used", Self.swapText(memory)),
                ])
            } else {
                WidgetCaption("Unavailable")
            }
        }
    }

    private static func swapText(_ memory: MemorySnapshot) -> String {
        guard memory.swapTotal > 0 else { return "None" }
        let used = SystemActivityFormatting.bytes(memory.swapUsed)
        let total = SystemActivityFormatting.bytes(memory.swapTotal)
        return "\(used) of \(total)"
    }

    // MARK: Disk

    @ViewBuilder
    private var diskSection: some View {
        let disk = snapshot.disk
        let color = SystemActivityStyle.diskColor(disk)
        VStack(alignment: .leading, spacing: 8) {
            MetricHeader(
                title: disk?.name ?? "Disk",
                systemImage: SystemActivityMetric.disk.systemImage,
                value: disk.map { SystemActivityFormatting.percent($0.usedFraction) } ?? "—%",
                color: color,
                progress: disk?.usedFraction ?? 0)

            if let disk {
                SegmentedBar(segments: [.init(id: 0, fraction: disk.usedFraction, color: color)])
                    .frame(height: 8)
                let used = SystemActivityFormatting.bytes(disk.used)
                let total = SystemActivityFormatting.bytes(disk.total)
                let available = SystemActivityFormatting.bytes(disk.available)
                WidgetCaption("\(used) of \(total) used · \(available) available")
            } else {
                WidgetCaption("Unavailable")
            }
        }
    }
}

/// Ring, title and headline figure for one section of the popover.
private struct MetricHeader: View {
    let title: String
    let systemImage: String
    let value: String
    let color: Color
    let progress: Double

    var body: some View {
        HStack(spacing: 10) {
            ActivityRing(progress: progress, color: color, lineWidth: 3.5)
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                }
            Text(title).fontWeight(.medium).lineLimit(1)
            Spacer(minLength: 8)
            Text(value).monospacedDigit().fontWeight(.semibold)
        }
    }
}

/// One thin bar per core, user time in the core's color and system time lighter above it.
private struct CoreBars: View {
    let cores: [CPUUsage]

    var body: some View {
        HStack(alignment: .bottom, spacing: cores.count > 16 ? 1.5 : 3) {
            ForEach(Array(cores.enumerated()), id: \.offset) { _, core in
                let color = SystemActivityStyle.cpuColor(core)
                GeometryReader { proxy in
                    let height = proxy.size.height
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1.5).fill(.primary.opacity(0.08))
                        VStack(spacing: 0) {
                            Rectangle().fill(color.opacity(0.5))
                                .frame(height: max(0, height * core.system))
                            Rectangle().fill(color)
                                .frame(height: max(0, height * core.user))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                    }
                }
                .help("Core \(core.total == 0 ? "idle" : SystemActivityFormatting.percent(core.total))")
            }
        }
        .animation(.easeOut(duration: 0.4), value: cores)
    }
}

/// Two-column label/value list for the memory breakdown.
private struct DetailGrid: View {
    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0).foregroundStyle(.secondary)
                    Text(row.1).monospacedDigit().gridColumnAlignment(.trailing)
                }
            }
        }
        .font(.caption)
    }
}
