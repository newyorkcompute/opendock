import DockCore
import DockWidgetKit
import SwiftUI

/// Live CPU, memory and disk gauges, with per-core detail in the popover.
///
/// Settings (all "true"/"false"):
/// - `showCPU`, `showMemory`, `showDisk`: which gauges the tile shows (default "true")
/// - `showCPUHistory`: draw the CPU figure with a sparkline of the last minute instead of
///   a ring (default "true")
public enum SystemActivityWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.systemActivity
    public static let displayName = "System Activity"
    public static let systemImage = "gauge.with.dots.needle.33percent"
    public static let summary = "CPU, memory and disk use at a glance."

    public static var defaultSettings: [String: String] {
        [
            SystemActivitySettings.showCPU: "true",
            SystemActivitySettings.showMemory: "true",
            SystemActivitySettings.showDisk: "true",
            SystemActivitySettings.showCPUHistory: "true",
        ]
    }

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(SystemActivityTileView(instance: instance))
    }

    public static func makePopout(instance: WidgetInstance) -> AnyView? {
        AnyView(SystemActivityPopoutView())
    }

    public static func makeSettingsView(instance: WidgetInstance) -> AnyView? {
        AnyView(SystemActivitySettingsView(instance: instance))
    }
}

/// The three things the tile can show, in display order.
enum SystemActivityMetric: CaseIterable, Identifiable {
    case cpu
    case memory
    case disk

    var id: Self { self }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .disk: "Disk"
        }
    }

    var systemImage: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        }
    }

    var settingKey: String {
        switch self {
        case .cpu: SystemActivitySettings.showCPU
        case .memory: SystemActivitySettings.showMemory
        case .disk: SystemActivitySettings.showDisk
        }
    }
}

/// Setting keys and parsing helpers shared by the views.
enum SystemActivitySettings {
    static let showCPU = "showCPU"
    static let showMemory = "showMemory"
    static let showDisk = "showDisk"
    static let showCPUHistory = "showCPUHistory"

    static func bool(_ key: String, in instance: WidgetInstance, default value: Bool = true) -> Bool {
        guard let raw = instance.settings[key] else { return value }
        return raw != "false"
    }

    /// The metrics the tile shows. Falls back to CPU when every toggle is off, so the
    /// tile never renders empty.
    static func metrics(in instance: WidgetInstance) -> [SystemActivityMetric] {
        let enabled = SystemActivityMetric.allCases.filter { bool($0.settingKey, in: instance) }
        return enabled.isEmpty ? [.cpu] : enabled
    }
}
