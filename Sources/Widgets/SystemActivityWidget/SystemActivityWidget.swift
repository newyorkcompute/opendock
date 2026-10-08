import DockCore
import DockWidgetKit
import SwiftUI

/// Live CPU, memory and disk gauges, with per-core detail in the popover. The settings
/// keys are declared in `SystemActivitySettings` and listed in `docs/widgets.md`.
public enum SystemActivityWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.systemActivity
    public static let displayName = "System Activity"
    public static let systemImage = "gauge.with.dots.needle.33percent"
    public static let summary = "CPU, memory and disk use at a glance."
    public static let settingsSchema = SystemActivitySettings.schema

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

    var settingKey: WidgetSettingKey {
        switch self {
        case .cpu: SystemActivitySettings.showCPU
        case .memory: SystemActivitySettings.showMemory
        case .disk: SystemActivitySettings.showDisk
        }
    }
}

/// The system activity widget's settings keys.
enum SystemActivitySettings {
    static let showCPU = WidgetSettingKey(
        "showCPU", type: .bool, default: "true",
        summary: "Show the CPU gauge.")
    static let showMemory = WidgetSettingKey(
        "showMemory", type: .bool, default: "true",
        summary: "Show the memory ring.")
    static let showDisk = WidgetSettingKey(
        "showDisk", type: .bool, default: "true",
        summary: "Show the startup disk ring.")
    static let showCPUHistory = WidgetSettingKey(
        "showCPUHistory", type: .bool, default: "true",
        summary: "Draw CPU as a sparkline of the last minute instead of a ring.")

    static let schema = WidgetSettingsSchema([showCPU, showMemory, showDisk, showCPUHistory])

    /// The metrics the tile shows. Falls back to CPU when every toggle is off, so the
    /// tile never renders empty.
    static func metrics(in instance: WidgetInstance) -> [SystemActivityMetric] {
        let enabled = SystemActivityMetric.allCases.filter { $0.settingKey.boolValue(in: instance.settings) }
        return enabled.isEmpty ? [.cpu] : enabled
    }
}
