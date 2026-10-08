import DockCore
import DockWidgetKit
import SwiftUI

/// Artwork, title and artist for whatever is playing in any app, with play/pause and
/// skip controls. Click the tile for a larger view with the album, position and player.
///
/// Settings: `showControls` ("true"/"false", default "true") and `showWhenIdle`
/// ("true"/"false", default "false"). When nothing is playing and `showWhenIdle` is off,
/// the tile takes no space at all.
public enum NowPlayingWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.nowPlaying
    public static let displayName = "Now Playing"
    public static let systemImage = "music.note"
    public static let summary = "What's playing, with play/pause and skip."

    public static var defaultSettings: [String: String] {
        [
            NowPlayingSettings.showControls: "true",
            NowPlayingSettings.showWhenIdle: "false",
        ]
    }

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(NowPlayingTileView(instance: instance))
    }

    public static func makePopout(instance: WidgetInstance) -> AnyView? {
        AnyView(NowPlayingPopoutView())
    }

    public static func makeSettingsView(instance: WidgetInstance) -> AnyView? {
        AnyView(NowPlayingSettingsView(instance: instance))
    }
}

/// Setting keys and parsing helpers shared by the Now Playing views.
enum NowPlayingSettings {
    static let showControls = "showControls"
    static let showWhenIdle = "showWhenIdle"

    static func bool(_ key: String, in instance: WidgetInstance, default value: Bool) -> Bool {
        guard let raw = instance.settings[key] else { return value }
        return raw == "true"
    }

    static func showControls(in instance: WidgetInstance) -> Bool {
        bool(showControls, in: instance, default: true)
    }

    static func showWhenIdle(in instance: WidgetInstance) -> Bool {
        bool(showWhenIdle, in: instance, default: false)
    }
}
