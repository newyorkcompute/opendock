import AppKit
import SwiftUI
import SystemServices

/// Detail view shown when the battery tile is clicked: every power source with
/// its state, time remaining and condition.
struct BatteryPopoutView: View {
    @State private var monitor = PowerSourceMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Battery").font(.headline)

            if monitor.sources.isEmpty {
                Label("Powered by adapter", systemImage: "powerplug.fill")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(monitor.sources) { source in
                        PowerSourceRow(source: source, isPluggedIn: monitor.isPluggedIn)
                    }
                }
            }

            Divider()

            Button("Open Battery Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings-extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
        .onAppear { monitor.refresh() }
    }
}

private struct PowerSourceRow: View {
    let source: PowerSource
    let isPluggedIn: Bool

    private var color: Color {
        BatteryFormatting.color(percentage: source.percentage, isCharging: source.isCharging)
    }

    var body: some View {
        HStack(spacing: 10) {
            ProgressRing(progress: Double(source.percentage ?? 0) / 100, color: color, lineWidth: 3.5)
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: source.isCharging ? "bolt.fill" : symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(source.name).lineLimit(1)
                    Spacer(minLength: 8)
                    if let percentage = source.percentage {
                        Text("\(percentage)%").monospacedDigit().fontWeight(.semibold)
                    }
                }
                ForEach(details, id: \.self) { line in
                    Text(line).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var symbol: String {
        switch source.kind {
        case .accessory: BatteryFormatting.symbol(forAccessory: source.name)
        case .ups: "bolt.batteryblock.fill"
        default: BatteryFormatting.batterySymbol(percentage: source.percentage)
        }
    }

    private var details: [String] {
        var lines: [String] = []
        if source.isCharged {
            lines.append("Fully charged")
        } else if source.isCharging {
            lines.append(
                source.minutesToFull.map { "Charging · \(BatteryFormatting.duration(minutes: $0)) to full" }
                    ?? "Charging")
        } else if source.kind == .internalBattery, isPluggedIn {
            lines.append("Plugged in, not charging")
        } else {
            lines.append(
                source.minutesToEmpty.map { "\(BatteryFormatting.duration(minutes: $0)) remaining" } ?? "On battery")
        }
        if let condition = source.condition ?? source.health {
            lines.append("Condition: \(condition)")
        }
        return lines
    }
}
