# AGENTS.md

Instructions for coding agents working on OpenDock, a native macOS dock that runs as a menu
bar app. [CONTRIBUTING.md](CONTRIBUTING.md) is the full guide for humans; if the two
disagree, CONTRIBUTING wins.

## Layout

OpenDock is a pure Swift Package with no Xcode project. Don't add one.

| Path | What's there |
| --- | --- |
| `Sources/DockCore` | Models, profiles, geometry, and persistence (`DockStorage`, `DockStore`). No UI. |
| `Sources/SystemServices` | Wrappers over macOS APIs: running apps, launching, icons, power, EventKit, hot keys, hiding Apple's Dock. |
| `Sources/DockWidgetKit` | The `DockWidget` protocol, `WidgetRegistry`, shared tile views, environment values. |
| `Sources/Widgets/*` | One target per built-in widget (`ClockWidget`, `BatteryWidget`, `CalendarWidget`). |
| `Sources/DockShell` | The dock panel: `DockPanel`, `DockController` (frame math, auto-hide, magnification), views, drag and drop. |
| `App/OpenDock` | The `@main` menu bar app, the AppKit-hosted Settings window, and menus. |
| `App/Resources` | `Info.plist`, entitlements, app icon. |
| `Tests/DockCoreTests`, `Tests/SystemServicesTests` | Unit tests. |
| `scripts/` | `build-app.sh` wraps the SwiftPM binary into `build/OpenDock.app`. |

## Commands

Building needs macOS with Xcode 26 or later (Swift 6.2+, macOS 26 SDK).

| Command | What it does |
| --- | --- |
| `make build` | Debug build and `.app` bundle |
| `make run` | Debug build, then (re)launch the app |
| `make test` | Unit tests (`swift test`) |
| `make release-native` | Optimized (`-O`) build and bundle for this Mac's architecture |
| `make format` | Format Swift sources in place (swift-format, per `.swift-format`) |
| `make lint` | Check formatting and lint rules, as CI does |

Before you open or update a PR, run `make format`, `make lint`, `make test`, and
`make release-native`, and make sure none of them adds warnings. CI also builds with `-O`, and some compiler crashes only show up there.
If several agents share a checkout, give each its own build directory
(`swift build --scratch-path .build-<name>`, same for `swift test`) and its own set of files.

App logs: `log stream --predicate 'subsystem == "com.newyorkcompute.opendock"' --level debug`

## Rules

- **Concurrency:** everything compiles under Swift 6 strict concurrency. UI targets
  (`DockWidgetKit`, `DockShell`, `Widgets/*`, `OpenDock`) use `.defaultIsolation(MainActor.self)`.
  `DockCore` and `SystemServices` don't, so mark UI-facing types there `@MainActor` explicitly.
- **Observation:** `@Observable` only. No `ObservableObject`, `@Published`, or Combine.
- **Tests:** Swift Testing only (`import Testing`, `@Suite`, `@Test`, `#expect`), never XCTest.
  Put logic that doesn't need a screen in `DockCore` so it can be tested.
- **Persistence:** change the layout and settings only through `DockStore` methods;
  `store.document` is `private(set)`. `dock.json` is versioned with tolerant decoding: add
  fields with defaults, never rename or remove them.
- **Widget IDs:** never rename a widget type ID (`BuiltInWidgetID.*`,
  `com.newyorkcompute.opendock.widget.*`). They're stored in users' `dock.json` files.
- **Generic classes in UI targets** need an explicit, empty, nonisolated `deinit {}`, like
  `DockHostingView` in `Sources/DockShell/DockPanel.swift`. Under main-actor default isolation
  the implicit deinit is isolated, and Swift 6.3.3 segfaults on it with `-O`. `isolated deinit`
  crashes the same way. Only `-O` builds catch this.
- **macOS 26 APIs:** the deployment target is macOS 15. Put Liquid Glass and any other
  macOS 26 API behind `if #available(macOS 26, *)`, with a frosted-material fallback.

CONTRIBUTING's [code conventions](CONTRIBUTING.md#code-conventions) cover the rest.

## Cursor and pstack

`.cursor/settings.json` enables the pstack plugin for Cursor. Its skills cover how to work
(reproduce first, keep changes small, verify); this file covers what's specific to OpenDock.
When a pstack skill asks for the repo's checks, run the ones under [Commands](#commands).

## Pull requests

Fill in [the PR template](.github/PULL_REQUEST_TEMPLATE.md) and follow
[AI-assisted contributions](CONTRIBUTING.md#ai-assisted-contributions). A human is responsible
for every PR. Don't tick checklist boxes for them, and don't claim manual testing that didn't
happen: unit tests and CI can't run the dock, so say what still needs testing on a real Mac.
