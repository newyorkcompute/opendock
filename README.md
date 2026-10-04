# OpenDock

An open-source custom Dock for macOS with widgets. Inspired by [Dockset](https://dockset.app).

**Status: early MVP. Requires macOS 15 or later.**

OpenDock is a floating dock panel at the bottom of your screen. It holds apps, folders,
spacers, and small live widgets. It runs as a menu bar app and does not replace or modify
Apple's Dock. You can keep both, or hide Apple's.

## Features

- Floating dock with Liquid Glass on macOS 26, and Frosted or Solid materials as alternatives
- Apps, folders and files, and small or regular spacers
- Running-app indicators, with an option to show running apps that aren't pinned
- Auto-hide with a configurable delay
- Drag items in the dock to reorder them, and drop apps or folders from Finder to add them
- Widgets: Clock, Battery, and Calendar
- Settings window with General, Dock Items, Widgets, and About tabs
- Export and import your layout as JSON
- Launch at login
- Menu bar menu for showing and hiding the dock, adding items, and backups

## Build and run

Requirements: macOS 15+, and Xcode 26+ or the Swift 6.2+ command line tools.

```sh
make run
# or
scripts/build-app.sh --debug
open build/OpenDock.app
```

`make release` builds an optimized bundle. `make test` runs the unit tests.

Notes:

- If the build fails with a license error, run `sudo xcodebuild -license accept`.
- The app is ad-hoc signed. macOS ties privacy permissions to the signature, so the
  Calendar permission prompt shows up again after each rebuild.
- Launch at login only works from the `.app` bundle, not from `swift run`.
- Your layout is stored in `~/Library/Application Support/OpenDock/dock.json`.

## Architecture

OpenDock is a single Swift Package with no Xcode project. `scripts/build-app.sh` wraps the
built binary in a signed `.app` bundle.

| Target | Role |
| --- | --- |
| `DockCore` | Models (`DockItem`, `DockProfile`, `DockSettings`) and JSON persistence (`DockStore`). No UI, fully unit-tested. |
| `DockWidgetKit` | The widget contract (`DockWidget`), the `WidgetRegistry`, shared tile views, and environment values. |
| `SystemServices` | Thin wrappers over macOS APIs: running apps, power sources, EventKit, icons, launching. |
| `Widgets/*` | One target per built-in widget (`ClockWidget`, `BatteryWidget`, `CalendarWidget`). |
| `DockShell` | The dock panel: window, positioning, auto-hide, item views, drag and drop. |
| `OpenDock` (`App/`) | The menu bar app: wires everything together, plus the menu, Settings window, and launch at login. |

UI targets compile with main-actor default isolation under Swift 6 strict concurrency.

## Writing a widget

A widget is a type that conforms to `DockWidget`. The dock stores `WidgetInstance` values
(a type ID plus a `[String: String]` settings bag) and asks the registry to render them.

```swift
import DockCore
import DockWidgetKit
import SwiftUI

public enum HelloWidget: DockWidget {
    public static let typeID = "com.example.widget.hello"   // stable, never change it
    public static let displayName = "Hello"
    public static let systemImage = "hand.wave"
    public static let summary = "Says hello."
    public static let defaultSettings = ["name": "World"]

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(HelloTile(instance: instance))
    }

    // Optional: makePopout(instance:) for a click-to-open popover and
    // makeSettingsView(instance:) for options in Settings > Dock Items.
}

struct HelloTile: View {
    let instance: WidgetInstance

    var body: some View {
        WidgetTile {
            WidgetPrimaryText("Hello, \(instance.settings["name"] ?? "World")")
        }
    }
}
```

Guidelines:

- Wrap the content in `WidgetTile` and use `WidgetPrimaryText` and `WidgetSecondaryText`
  so the tile scales with the icon-size setting (`\.dockIconSize`).
- Pause polling when `\.dockIsVisible` is false.
- Save settings through `\.widgetUpdateSettings`, never through your own files.

Then add a target under `Sources/Widgets/` in `Package.swift`, add it as a dependency of
`OpenDock`, and register it in `AppDelegate` with `registry.register([...])`.

## Roadmap

Tracked as [GitHub issues](https://github.com/newyorkcompute/opendock/issues); the ones
labeled `good first issue` are self-contained. Highlights:

- Profiles, with switching by hotkey or Focus mode
- More widgets: Now Playing, Weather, Reminders, System Activity, Network, Timer, Sticky
  Note, Stocks
- Left and right screen edges
- Magnification
- Notification badges
- Minimized windows in the dock
- Automatic updates with Sparkle
- Homebrew cask

## Contributing

Issues and pull requests are welcome. Please keep changes focused, match the existing
style, and run `swift build` and `swift test` before opening a PR. New widgets are a
great place to start.

## License

MIT. See [LICENSE](LICENSE).
