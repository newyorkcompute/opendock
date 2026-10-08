import DockCore
import DockWidgetKit
import SwiftUI

/// Artwork, title and artist for whatever is playing in any app, with play/pause and
/// skip controls. Click the tile for a larger view with the album, position and player.
/// The settings keys are declared in `NowPlayingSettings` and listed in `docs/widgets.md`.
public enum NowPlayingWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.nowPlaying
    public static let displayName = "Now Playing"
    public static let systemImage = "music.note"
    public static let summary = "What's playing, with play/pause and skip."
    public static let settingsSchema = NowPlayingSettings.schema

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

/// The Now Playing widget's settings keys.
enum NowPlayingSettings {
    static let showControls = WidgetSettingKey(
        "showControls", type: .bool, default: "true",
        summary: "Show previous, play/pause and next buttons on the tile.")
    static let showWhenIdle = WidgetSettingKey(
        "showWhenIdle", type: .bool, default: "false",
        summary: "Keep the tile in the dock while nothing is playing. When off, it takes no space at all.")

    static let schema = WidgetSettingsSchema([showControls, showWhenIdle])
}
