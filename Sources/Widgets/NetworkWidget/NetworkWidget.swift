import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// Live download and upload speeds with a sparkline of the last minute, and the
/// interfaces with their addresses in the popover. The settings keys are declared in
/// `NetworkSettings` and listed in `docs/widgets.md`.
public enum NetworkWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.network
    public static let displayName = "Network"
    public static let systemImage = "arrow.up.arrow.down"
    public static let summary = "Download and upload speeds."
    public static let settingsSchema = NetworkSettings.schema

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(NetworkTileView(instance: instance))
    }

    public static func makePopout(instance: WidgetInstance) -> AnyView? {
        AnyView(NetworkPopoutView(instance: instance))
    }

    public static func makeSettingsView(instance: WidgetInstance) -> AnyView? {
        AnyView(NetworkSettingsView(instance: instance))
    }
}

/// The two directions the tile can show, in display order.
enum NetworkDirection: CaseIterable, Identifiable {
    case download
    case upload

    var id: Self { self }

    var title: String {
        switch self {
        case .download: "Download"
        case .upload: "Upload"
        }
    }

    var systemImage: String {
        switch self {
        case .download: "arrow.down"
        case .upload: "arrow.up"
        }
    }

    var settingKey: WidgetSettingKey {
        switch self {
        case .download: NetworkSettings.showDownload
        case .upload: NetworkSettings.showUpload
        }
    }

    func bytesPerSecond(in throughput: NetworkThroughput) -> Double {
        switch self {
        case .download: throughput.downloadBytesPerSecond
        case .upload: throughput.uploadBytesPerSecond
        }
    }
}

/// The network widget's settings keys.
enum NetworkSettings {
    static let showDownload = WidgetSettingKey(
        "showDownload", type: .bool, default: "true",
        summary: "Show the download speed.")
    static let showUpload = WidgetSettingKey(
        "showUpload", type: .bool, default: "true",
        summary: "Show the upload speed.")
    static let showHistory = WidgetSettingKey(
        "showHistory", type: .bool, default: "true",
        summary: "Draw a sparkline of the last minute beside the speeds.")
    static let unit = WidgetSettingKey(
        "unit", type: .choice(NetworkRateUnit.allCases.map(\.rawValue)), default: NetworkRateUnit.bytes.rawValue,
        summary:
            "Measure in bytes per second (KB/s, MB/s), as Finder counts, or in bits per second (Kb/s, Mb/s), as internet plans are sold."
    )
    static let interface = WidgetSettingKey(
        "interface", type: .text, default: "",
        summary:
            "The one interface to measure, by its BSD name such as \"en0\". Empty means every connected Wi-Fi, Ethernet and cellular link, leaving out loopback, VPN tunnels and the system's own interfaces."
    )

    static let schema = WidgetSettingsSchema([showDownload, showUpload, showHistory, unit, interface])

    /// The directions the tile shows. Falls back to both when every toggle is off, so
    /// the tile never renders empty.
    static func directions(in instance: WidgetInstance) -> [NetworkDirection] {
        let enabled = NetworkDirection.allCases.filter { $0.settingKey.boolValue(in: instance.settings) }
        return enabled.isEmpty ? NetworkDirection.allCases : enabled
    }

    static func unit(in instance: WidgetInstance) -> NetworkRateUnit {
        NetworkRateUnit(rawValue: unit.value(in: instance.settings)) ?? .bytes
    }

    static func selection(in instance: WidgetInstance) -> NetworkInterfaceSelection {
        NetworkInterfaceSelection(settingValue: interface.value(in: instance.settings))
    }
}

/// Colors shared by the tile and the popover.
enum NetworkStyle {
    static func color(for direction: NetworkDirection) -> Color {
        switch direction {
        case .download: .blue
        case .upload: .orange
        }
    }
}
