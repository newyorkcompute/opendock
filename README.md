<div align="center">

<img src="docs/assets/app-icon.png" width="128" height="128" alt="OpenDock app icon">

# OpenDock

**An open-source custom Dock for macOS, with live widgets.**

[![CI](https://github.com/newyorkcompute/opendock/actions/workflows/ci.yml/badge.svg)](https://github.com/newyorkcompute/opendock/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Swift 6.2+](https://img.shields.io/badge/Swift-6.2%2B-F05138?logo=swift&logoColor=white)

[Features](#features) · [Widgets](#widgets) · [Build and run](#build-and-run) ·
[Writing a widget](#writing-a-widget) · [Contributing](#contributing)

</div>

<p align="center">
  <picture>
    <source media="(prefers-reduced-motion: reduce)" srcset="docs/assets/dock-magnification.png">
    <img src="docs/assets/dock-magnification.gif" alt="The OpenDock dock on a macOS desktop. As the pointer moves along it, icons magnify with a smooth falloff, push their neighbors aside, and show a name label above the hovered item. The dock holds Finder, Mail, Messages, Calendar, Notes, Music, and System Settings, then the Calendar, Clock, and Battery widgets, Safari, and a Downloads folder.">
  </picture>
</p>

> [!NOTE]
> OpenDock is an early MVP. It requires macOS 15 or later, and there are no prebuilt
> releases yet, so for now you [build it from source](#build-and-run). Releases won't be
> notarized at first, so macOS blocks them until you allow them. Before you do, you can check
> that a zip was built by this repo's CI with
> `gh attestation verify OpenDock-*.zip --repo newyorkcompute/opendock`
> (see [Releasing](RELEASING.md#verifying-a-download)).

OpenDock is a floating dock panel at the bottom of your screen. It holds apps, folders,
spacers, and small live widgets. It runs as a menu bar app and does not replace Apple's
Dock. You can keep both, or have OpenDock hide Apple's while it runs. Inspired by [Dockset](https://dockset.app).

## Features

<table>
  <tr>
    <td width="50%"><img src="docs/assets/dock-hover-mail.png" alt="The pointer over Mail: Mail and its neighbors are magnified, and a Mail label floats above it."></td>
    <td width="50%"><img src="docs/assets/dock-hover-end.png" alt="The pointer over the Downloads folder at the end of the dock: Downloads and Safari are magnified, with a Downloads label above. The Clock and Battery widgets sit beside them."></td>
  </tr>
  <tr>
    <td>Icons near the pointer grow with a smooth falloff and push their neighbors aside.</td>
    <td>Widgets grow too, more gently, and slide out of the way.</td>
  </tr>
</table>

- Floating dock with Liquid Glass on macOS 26, and Frosted or Solid materials as alternatives
- Apps, folders and files, small or regular spacers, and dividers. Click a divider for
  quick settings (hiding, magnification, position), like the Dock's separators
- Click and hold a folder (or choose Browse from its menu) to see what's in it: open items,
  step into subfolders, drag files out, and sort by name, date, or kind. A folder hops
  once when a new file lands in it, like Downloads in Apple's Dock
- The Trash at the end of the dock, like the Dock's: its icon shows whether it's empty, a
  click opens it in Finder, the menu empties it, and dropping files on it trashes them
  (dropping a dock item removes it from the dock). Settings > Dock Items can hide it
- Running-app indicators, with options to show running apps that aren't pinned and, after
  those, the apps you used last (like the Dock's recent apps)
- Magnification like the Dock's: icons near the pointer grow with a smooth falloff and
  push their neighbors aside, with an adjustable size and a name label above the hovered item.
  Widget tiles grow along with them, more gently, and stay sharp
- Auto-hide with a configurable delay. In full-screen apps, hold the pointer at the bottom
  edge for a moment to show the dock, like Apple's Dock
- Optionally hides Apple's Dock while it runs, and puts your Dock settings back when it quits
- Drag items in the dock to reorder them, and drop apps or folders from Finder to add them.
  Drag an item well away from the dock and hold it there a moment to remove it, with a
  puff of smoke, like the Dock
- Right-click an app to see its windows and bring one to the front, and optionally click
  the active app's icon to minimize its windows (see [Window management](#window-management))
- Profiles: keep several layouts (say, Work and Home) and switch between them from the menu
  bar, with your own global shortcuts, or by swiping sideways on the dock (⌘-scroll works
  with a mouse). A Focus mode can switch profiles too (see [Focus modes](#focus-modes))
- Keyboard control: a global shortcut shows the dock and selects an item; arrow keys move
  along it, Return opens, Space browses a folder or opens a widget, Delete removes, Escape
  puts the keyboard back. The selection is announced to VoiceOver
- Widgets: Clock, Battery, Calendar, System Activity, Weather, Now Playing, Time Progress, Network, and
  Reminders
- Settings window with General, Profiles, Dock Items, Widgets, and About tabs
- Export and import your layout as JSON
- Launch at login
- Menu bar menu for showing and hiding the dock, adding items, and backups
- A short welcome window on first launch, which can switch the starter apps for the ones
  in Apple's Dock

## Widgets

<p align="center">
  <img src="docs/assets/dock-widgets.png" width="340" alt="The Calendar, Clock, and Battery tiles in the dock: Sun 4 with Oct 4 and Tap to allow, 8:17 PM with Sun 4, and 100% with Charging.">
</p>

Widgets are small live tiles that sit in the dock next to your apps. Click one to open a
popover with more detail. Each widget has its own options in Settings > Dock Items.

| Widget | In the dock | Click for | Options |
| --- | --- | --- | --- |
| Calendar | Today's date and your next event | Today's events, with a Join button for meetings that have a link | Show next event |
| Clock | The time, with the date or your own label below | The full date, time zone, and a month calendar | Seconds, date, time zone, label |
| Battery | Charge level and power source | Each battery, including connected accessories, and a shortcut to Battery Settings | Percentage, accessory batteries |
| System Activity | CPU with a one-minute sparkline, plus memory and disk rings | Per-core CPU and load average, the memory breakdown and swap, the startup disk, and a shortcut to Activity Monitor | Which of CPU, memory, and disk to show; CPU history |
| Weather | Current conditions and temperature for your location or a city | Feels-like, humidity and wind, the next 12 hours, and a 4-day forecast | °C or °F, caption, location |
| Now Playing | Artwork, title and artist of whatever is playing in any app, with previous, play/pause and next buttons; hidden while nothing plays | The album, a position bar, bigger controls, and an Open button for the player | Buttons, stay visible when idle |
| Time Progress | How much of the year, month, week, and day has passed, as bars or rings with a percentage | All four periods with a precise percentage, the day of the period, and what's left | Which periods to show; bars or rings |
| Network | Download and upload speeds with a one-minute sparkline | A bigger chart, each connected interface with its speeds and addresses, and a shortcut to Network Settings | Which speeds to show, history, bytes or bits, interface |
| Reminders | How many reminders are waiting, and the list's name | Your reminders grouped into overdue, today, upcoming, and no date, each with a circle to complete it, and a shortcut to Reminders | Which list, all or only due today, list name |

The Calendar widget asks for calendar access when it first appears (on a fresh install,
once the welcome window is closed), and the Reminders widget asks for reminders access the
same way. Without access they show "Tap to allow", and their popovers have a button to allow
access or open Privacy Settings. The Now Playing widget reads the system's Now Playing (the same data as Control
Center) through a small helper run by `/usr/bin/perl`; if that isn't available it asks
Music and Spotify directly, and macOS asks you once to allow that. The keys each widget stores in
`dock.json` are listed in [docs/widgets.md](docs/widgets.md). To build your own widget,
see [Writing a widget](#writing-a-widget).

The Weather widget uses [Open-Meteo](https://open-meteo.com/) (free, no account) and asks for
location access only when a tile set to Current Location is in the dock; you can pick a city
instead in its settings. It refreshes every 15 minutes while the dock is visible and keeps the
last forecast when offline.

## Window management

Right-click a running app in the dock to list its open windows, like Apple's Dock: the
current one is checked, minimized ones have a diamond, and choosing one brings it to the
front. With "Click the active app's icon to minimize its windows" on (Settings > General >
Behavior), clicking the icon of the app you're using minimizes its windows, and clicking it
again restores them.

Both need Accessibility access (as do app badges), because macOS only lets apps see and
arrange other apps' windows through the Accessibility API. OpenDock doesn't ask at launch.
It asks when you turn on click-to-minimize or badges, or choose "Allow Access to Windows…"
in an app's menu, and Settings > General > Accessibility shows whether it's allowed; you
can allow it in System Settings > Privacy & Security > Accessibility at any time. OpenDock
only reads window titles and whether a window is minimized; it doesn't read what's in your
windows. Without access, the dock works as before.

## Focus modes

In Settings > Profiles > Focus, pick a profile for each Focus mode (Work, Sleep, Do Not
Disturb, and any you've made). When that Focus turns on, the dock switches to the profile;
"Don't change" leaves the dock alone.
When Focus turns off, the dock goes back to the profile it showed before, or stays, as you
choose. If you switch profiles yourself while a Focus is on, that choice stands.

macOS doesn't offer apps a way to ask which Focus is on, so OpenDock reads it from the
Focus database in `~/Library/DoNotDisturb/DB`, which macOS protects: reading it needs
Full Disk Access. The Focus section explains this and opens System Settings > Privacy &
Security > Full Disk Access for you; after allowing OpenDock there, quit and reopen it.
OpenDock only reads your Focus settings and never changes them. Without access, profiles
work as before and Focus modes just don't switch them.

## Build and run

Requirements:

- macOS 15 or later to run OpenDock.
- Xcode 26 or later to build it, for Swift 6.2+ and the macOS 26 SDK. A stock Xcode is
  enough; you don't need a separate Swift toolchain. CI builds every change with the newest
  stable Xcode on GitHub's macOS 26 runner (currently Xcode 26.6 with Swift 6.3.3).

```sh
make run
# or
scripts/build-app.sh --debug
open build/OpenDock.app
```

`make release` builds an optimized bundle in `build/OpenDock.app`. `make test` runs the
unit tests.

Notes:

- If the build fails with a license error, run `sudo xcodebuild -license accept`.
- The app is ad-hoc signed. macOS ties privacy permissions to the signature, so the
  Calendar permission prompt shows up again after each rebuild. Accessibility access stops
  working too, even if System Settings still shows it as allowed: remove OpenDock from the
  list there and allow it again.
- Launch at login only works from the `.app` bundle, not from `swift run`.
- Your layout is stored in `~/Library/Application Support/OpenDock/dock.json`.

## Architecture

OpenDock is a single Swift Package. `scripts/build-app.sh` wraps the built binary in a signed
`.app` bundle. For Xcode's debugger, Instruments, or SwiftUI previews, `make xcodeproj`
generates a git-ignored project; see
[Working in Xcode](CONTRIBUTING.md#working-in-xcode) in CONTRIBUTING.

| Target | Role |
| --- | --- |
| `DockCore` | Models (`DockItem`, `DockProfile`, `DockSettings`) and JSON persistence (`DockStore`). No UI, fully unit-tested. |
| `DockWidgetKit` | The widget contract (`DockWidget`), the `WidgetRegistry`, shared tile views, and environment values. |
| `SystemServices` | Thin wrappers over macOS APIs: running apps, power sources, EventKit, icons, launching, hiding Apple's Dock. |
| `Widgets/*` | One target per built-in widget (`ClockWidget`, `BatteryWidget`, `CalendarWidget`, `SystemActivityWidget`, `WeatherWidget`). |
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

    // Every key the widget reads: name, value type, default, and a one-line description.
    // The settings UI, load-time validation, and docs/widgets.md all come from this.
    public static let settingsSchema = WidgetSettingsSchema([name])
    static let name = WidgetSettingKey("name", type: .text, default: "World", summary: "Who to greet.")

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
            // Reading through the key gives the default when the value is missing or invalid.
            WidgetPrimaryText("Hello, \(HelloWidget.name.value(in: instance.settings))")
        }
    }
}
```

Guidelines:

- Wrap the content in `WidgetTile` and use `WidgetPrimaryText` and `WidgetSecondaryText`
  so the tile scales with the icon-size setting (`\.dockIconSize`). Size anything else
  from `\.dockIconSize` too: it includes the tile's magnification, so the tile is laid
  out again, with sharp text, as it grows under the pointer.
- Pause polling when `\.dockIsVisible` is false.
- If the widget needs a permission, ask for it on its own only while
  `\.widgetsMayRequestAccess` is true. It's false while the welcome window is open on a
  fresh install.
- Save settings through `\.widgetUpdateSettings`, never through your own files. In a
  settings view, `updater.boolBinding(key, in: $instance)` and `stringBinding` give you
  bindings that read through the schema and persist each change.

Then add a target under `Sources/Widgets/` in `Package.swift`, add it as a dependency of
`BuiltInWidgets`, and append it to `BuiltInWidgets.all`. That registers it at launch,
validates its saved settings against the schema, and adds it to the widget docs; run
`make widget-docs` to regenerate [docs/widgets.md](docs/widgets.md).

## Roadmap

Tracked as [GitHub issues](https://github.com/newyorkcompute/opendock/issues); the ones
labeled `good first issue` are self-contained. Highlights:

- More widgets: Reminders, Timer, Sticky Note, Stocks
- Left and right screen edges
- Notification badges
- Minimized windows in the dock
- Automatic updates with Sparkle
- Homebrew cask

## Contributing

Issues and pull requests are welcome. Please keep changes focused, match the existing
style, and run `swift build` and `swift test` before opening a PR. New widgets are a
great place to start. See [CONTRIBUTING.md](CONTRIBUTING.md) for the conventions and how
to test, and the [Code of Conduct](CODE_OF_CONDUCT.md). Report security issues as described
in [SECURITY.md](SECURITY.md).

## License

MIT. See [LICENSE](LICENSE).
