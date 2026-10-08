import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// Settings for one Now Playing tile.
struct NowPlayingSettingsView: View {
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var instance: WidgetInstance
    @State private var monitor = NowPlayingMonitor.shared

    init(instance: WidgetInstance) {
        _instance = State(initialValue: instance)
    }

    var body: some View {
        Form {
            Toggle("Show play/pause and skip buttons", isOn: binding(NowPlayingSettings.showControls, default: true))
            Toggle(
                "Keep the tile visible when nothing is playing",
                isOn: binding(NowPlayingSettings.showWhenIdle, default: false))

            Section {
                Text(sourceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sourceDescription: String {
        if monitor.isUnavailable {
            return "OpenDock can't read what's playing on this Mac."
        }
        if let source = monitor.sourceName {
            return "Reads what's playing from \(source)."
        }
        let fallback = "If that isn't available, it asks Music and Spotify directly, which macOS will ask you to allow."
        return "Reads what's playing from the system's Now Playing, like Control Center. \(fallback)"
    }

    private func binding(_ key: String, default value: Bool) -> Binding<Bool> {
        Binding(
            get: { NowPlayingSettings.bool(key, in: instance, default: value) },
            set: { newValue in
                instance.settings[key] = newValue ? "true" : "false"
                updater(instance)
            }
        )
    }
}
