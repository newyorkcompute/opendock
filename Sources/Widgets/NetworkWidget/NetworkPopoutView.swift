import AppKit
import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// Detail view shown when the tile is clicked: a bigger chart of the last minute, then
/// every connected interface with its speeds and addresses.
struct NetworkPopoutView: View {
    let instance: WidgetInstance

    @State private var monitor = NetworkActivityMonitor.shared

    private var unit: NetworkRateUnit { NetworkSettings.unit(in: instance) }
    private var selection: NetworkInterfaceSelection { NetworkSettings.selection(in: instance) }
    private var snapshot: NetworkActivitySnapshot { monitor.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Network").font(.headline)

            totals
            Divider()
            interfaces
            Divider()

            Button("Open Network Settings") { SystemSettingsPane.network.open() }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        // The popover is only ever open while the dock is on screen.
        .task { await monitor.autoRefresh() }
    }

    // MARK: Totals

    @ViewBuilder
    private var totals: some View {
        let readings = snapshot.interfaces.map(\.reading)
        let series = monitor.history.series(for: selection, interfaces: readings)
        let throughput = snapshot.throughput(for: selection)
        VStack(alignment: .leading, spacing: 8) {
            NetworkSparkline(download: series.download, upload: series.upload, capacity: monitor.history.capacity)
                .frame(height: 56)
            HStack(spacing: 16) {
                ForEach(NetworkDirection.allCases) { direction in
                    SpeedLabel(
                        direction: direction,
                        text: throughput.map { NetworkFormatting.rate(direction.bytesPerSecond(in: $0), unit: unit) }
                            ?? "—")
                }
                Spacer(minLength: 0)
            }
            WidgetCaption(totalsCaption)
        }
    }

    private var totalsCaption: String {
        switch selection {
        case .automatic:
            let counted = snapshot.interfaces(matching: .automatic)
            if counted.isEmpty { return "No connected interface" }
            return "Last minute across " + counted.map(\.name).joined(separator: ", ")
        case let .named(name):
            return snapshot.isMissing(selection) ? "\(name) isn't connected" : "Last minute on \(name)"
        }
    }

    // MARK: Interfaces

    @ViewBuilder
    private var interfaces: some View {
        let listed = snapshot.listedInterfaces(selection: selection)
        if listed.isEmpty {
            Label("No network connection", systemImage: "wifi.slash")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(listed) { status in
                    InterfaceRow(status: status, unit: unit, isCounted: selection.includes(status.reading))
                }
            }
        }
    }
}

/// One direction's arrow and speed, in its color.
private struct SpeedLabel: View {
    let direction: NetworkDirection
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: direction.systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(NetworkStyle.color(for: direction))
            Text(text).monospacedDigit().fontWeight(.semibold)
        }
        .help(direction.title)
    }
}

/// Icon, name, speeds and addresses for one interface.
private struct InterfaceRow: View {
    let status: NetworkInterfaceStatus
    let unit: NetworkRateUnit
    /// Whether the tile's total includes this interface.
    let isCounted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status.reading.kind.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isCounted ? Color.accentColor : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(status.title).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(speeds).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                if status.reading.addresses.isEmpty {
                    WidgetCaption(status.reading.isRunning ? "No address" : "Not connected")
                } else {
                    ForEach(status.reading.addresses, id: \.self) { address in
                        WidgetCaption(address)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var speeds: String {
        guard let throughput = status.throughput else { return "—" }
        return NetworkDirection.allCases.map {
            NetworkFormatting.directedRate($0.bytesPerSecond(in: throughput), download: $0 == .download, unit: unit)
        }.joined(separator: "  ")
    }
}
