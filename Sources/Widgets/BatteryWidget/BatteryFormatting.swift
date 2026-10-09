import SwiftUI
import SystemServices

/// Presentation logic shared by the tile and the popout.
enum BatteryFormatting {
    /// Green when healthy or charging, yellow when getting low, red when critical.
    static func color(percentage: Int?, isCharging: Bool) -> Color {
        guard let percentage else { return .secondary }
        if isCharging || percentage >= 50 { return .green }
        return percentage >= 20 ? .yellow : .red
    }

    /// "2:14" from minutes.
    static func duration(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// Short caption for the internal battery / power adapter state.
    static func caption(for monitor: PowerSourceMonitor) -> String {
        guard monitor.hasBattery else { return "Power adapter" }
        if monitor.isFullyCharged { return "Charged" }
        if monitor.isCharging {
            return monitor.timeRemainingMinutes.map { "\(duration(minutes: $0)) to full" } ?? "Charging"
        }
        if monitor.isPluggedIn { return "Plugged in" }
        return monitor.timeRemainingMinutes.map { "\(duration(minutes: $0)) left" } ?? "On battery"
    }

    /// SF Symbol for an accessory, guessed from its name.
    static func symbol(forAccessory name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("mouse") { return "magicmouse" }
        if lower.contains("keyboard") { return "keyboard" }
        if lower.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        return "dot.radiowaves.left.and.right"
    }

    /// Battery glyph matching a charge level.
    static func batterySymbol(percentage: Int?) -> String {
        switch percentage ?? 0 {
        case 88...: "battery.100percent"
        case 63...: "battery.75percent"
        case 38...: "battery.50percent"
        case 13...: "battery.25percent"
        default: "battery.0percent"
        }
    }
}
