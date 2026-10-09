import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// The in-dock battery tile: a progress ring, the percentage and a caption,
/// plus up to two small rings for battery-reporting accessories.
struct BatteryTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge
    @State private var monitor = PowerSourceMonitor.shared

    /// Text beside the ring on the bottom edge, under it on a side edge.
    private var textAlignment: HorizontalAlignment { edge.isVertical ? .center : .leading }

    private var showPercentage: Bool { BatterySettings.showPercentage.boolValue(in: instance.settings) }
    private var showAccessories: Bool { BatterySettings.showAccessories.boolValue(in: instance.settings) }

    var body: some View {
        WidgetTile {
            WidgetStack(spacing: iconSize * (edge.isVertical ? 0.08 : 0.16)) {
                if monitor.hasBattery {
                    batteryContent
                } else {
                    desktopContent
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Laptop

    @ViewBuilder
    private var batteryContent: some View {
        let percentage = monitor.percentage
        let color = BatteryFormatting.color(percentage: percentage, isCharging: monitor.isCharging)
        let ringSize = iconSize * 0.6

        WidgetRing(fraction: Double(percentage ?? 0) / 100, color: color, lineWidth: max(2.5, iconSize * 0.07))
            .frame(width: ringSize, height: ringSize)
            .overlay {
                if monitor.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: ringSize * 0.38, weight: .bold))
                        .foregroundStyle(color)
                } else if monitor.isPluggedIn {
                    Image(systemName: "powerplug.fill")
                        .font(.system(size: ringSize * 0.34, weight: .bold))
                        .foregroundStyle(color)
                }
            }

        VStack(alignment: textAlignment, spacing: 0) {
            if showPercentage {
                WidgetPrimaryText(percentage.map { "\($0)%" } ?? "—%")
            }
            WidgetSecondaryText(BatteryFormatting.caption(for: monitor))
        }

        if showAccessories {
            accessoryRings
        }
    }

    @ViewBuilder
    private var accessoryRings: some View {
        let accessories = Array(monitor.accessories.prefix(2))
        if !accessories.isEmpty {
            HStack(spacing: iconSize * 0.08) {
                ForEach(accessories) { accessory in
                    let color = BatteryFormatting.color(
                        percentage: accessory.percentage, isCharging: accessory.isCharging)
                    let size = iconSize * 0.38
                    WidgetRing(
                        fraction: Double(accessory.percentage) / 100, color: color,
                        lineWidth: max(1.8, iconSize * 0.045)
                    )
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: BatteryFormatting.symbol(forAccessory: accessory.name))
                            .font(.system(size: size * 0.4, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .help("\(accessory.name): \(accessory.percentage)%")
                }
            }
        }
    }

    // MARK: Desktop

    @ViewBuilder
    private var desktopContent: some View {
        Image(systemName: "powerplug.fill")
            .font(.system(size: iconSize * 0.36, weight: .semibold))
            .foregroundStyle(.green)
        VStack(alignment: textAlignment, spacing: 0) {
            WidgetPrimaryText("AC")
            WidgetSecondaryText("Power adapter")
        }
    }

    private var accessibilityLabel: String {
        guard monitor.hasBattery else { return "Battery: on power adapter" }
        let level = monitor.percentage.map { "\($0) percent" } ?? "unknown level"
        return "Battery \(level), \(BatteryFormatting.caption(for: monitor))"
    }
}
