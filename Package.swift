// swift-tools-version: 6.2

import PackageDescription

/// Swift settings shared by every target.
let baseSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

/// UI-facing targets run on the main actor by default ("approachable concurrency").
/// Anything that needs to leave the main actor opts out explicitly with `nonisolated`.
let uiSettings: [SwiftSetting] = baseSettings + [
    .defaultIsolation(MainActor.self),
]

/// Every module the app links. The `OpenDock` executable depends on all of them, and the
/// `OpenDockModules` product exposes the same set to the generated Xcode project
/// (`App/project.yml`), whose app target compiles `App/OpenDock` itself and can only link
/// package products. Widgets reach the app through `BuiltInWidgets`.
let appModules = [
    "DockCore",
    "DockWidgetKit",
    "DockShell",
    "SystemServices",
    "BuiltInWidgets",
]

let package = Package(
    name: "OpenDock",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    products: [
        .executable(name: "OpenDock", targets: ["OpenDock"]),
        .library(name: "DockCore", targets: ["DockCore"]),
        .library(name: "DockWidgetKit", targets: ["DockWidgetKit"]),
        /// For the Xcode project only (`make xcodeproj`); see `appModules`.
        .library(name: "OpenDockModules", targets: appModules),
        /// Loaded by `/usr/bin/perl`, never by the app (see `Sources/NowPlayingHelper`).
        /// `scripts/build-app.sh` builds it and copies the dylib into `Contents/Frameworks`.
        .library(name: "OpenDockNowPlayingHelper", type: .dynamic, targets: ["NowPlayingHelper"]),
    ],
    targets: [
        // MARK: Foundation layers

        /// Pure models and persistence. No AppKit, no UI. Fully testable from the CLI.
        .target(
            name: "DockCore",
            swiftSettings: baseSettings
        ),

        /// Thin wrappers over macOS system APIs: running apps, power, EventKit, icons.
        .target(
            name: "SystemServices",
            dependencies: ["DockCore"],
            swiftSettings: baseSettings
        ),

        /// The widget contract: how a widget describes itself and renders into the dock.
        .target(
            name: "DockWidgetKit",
            dependencies: ["DockCore"],
            swiftSettings: uiSettings
        ),

        // MARK: Widgets (one target each)

        .target(
            name: "ClockWidget",
            dependencies: ["DockWidgetKit"],
            path: "Sources/Widgets/ClockWidget",
            swiftSettings: uiSettings
        ),
        .target(
            name: "BatteryWidget",
            dependencies: ["DockWidgetKit", "SystemServices"],
            path: "Sources/Widgets/BatteryWidget",
            swiftSettings: uiSettings
        ),
        .target(
            name: "CalendarWidget",
            dependencies: ["DockWidgetKit", "SystemServices"],
            path: "Sources/Widgets/CalendarWidget",
            swiftSettings: uiSettings
        ),
        .target(
            name: "SystemActivityWidget",
            dependencies: ["DockWidgetKit", "SystemServices"],
            path: "Sources/Widgets/SystemActivityWidget",
            swiftSettings: uiSettings
        ),
        .target(
            name: "WeatherWidget",
            dependencies: ["DockWidgetKit", "SystemServices"],
            path: "Sources/Widgets/WeatherWidget",
            swiftSettings: uiSettings
        ),
        .target(
            name: "NowPlayingWidget",
            dependencies: ["DockWidgetKit", "SystemServices"],
            path: "Sources/Widgets/NowPlayingWidget",
            swiftSettings: uiSettings
        ),
        .target(
            name: "TimeProgressWidget",
            dependencies: ["DockWidgetKit"],
            path: "Sources/Widgets/TimeProgressWidget",
            swiftSettings: uiSettings
        ),
        .target(
            name: "NetworkWidget",
            dependencies: ["DockWidgetKit", "SystemServices"],
            path: "Sources/Widgets/NetworkWidget",
            swiftSettings: uiSettings
        ),
        .target(
            name: "RemindersWidget",
            dependencies: ["DockWidgetKit", "SystemServices"],
            path: "Sources/Widgets/RemindersWidget",
            swiftSettings: uiSettings
        ),
        /// Focus Timer, Countdown, Stopwatch and Alarm: four widgets sharing one model.
        .target(
            name: "TimerWidgets",
            dependencies: ["DockWidgetKit", "SystemServices"],
            path: "Sources/Widgets/TimerWidgets",
            swiftSettings: uiSettings
        ),
        .target(
            name: "StickyNoteWidget",
            dependencies: ["DockWidgetKit"],
            path: "Sources/Widgets/StickyNoteWidget",
            swiftSettings: uiSettings
        ),
        .target(
            name: "StocksWidget",
            dependencies: ["DockWidgetKit", "SystemServices"],
            path: "Sources/Widgets/StocksWidget",
            swiftSettings: uiSettings
        ),
        .target(
            name: "ShortcutsWidget",
            dependencies: ["DockWidgetKit", "SystemServices"],
            path: "Sources/Widgets/ShortcutsWidget",
            swiftSettings: uiSettings
        ),
        .target(
            name: "AirDropWidget",
            dependencies: ["DockWidgetKit", "SystemServices"],
            path: "Sources/Widgets/AirDropWidget",
            swiftSettings: uiSettings
        ),
        /// The host for widgets written in JavaScript (see `docs/scripted-widgets.md`).
        .target(
            name: "ScriptedWidgets",
            dependencies: ["DockWidgetKit", "ScriptedWidgetRuntime", "SystemServices"],
            path: "Sources/Widgets/ScriptedWidgets",
            swiftSettings: uiSettings
        ),

        // MARK: Helpers

        /// Scripted widgets' package format, tile description, limits, and the JavaScriptCore
        /// engine that runs them. No UI and no main-actor default, so the engine's actor and
        /// the models can be used from anywhere and tested from the CLI.
        .target(
            name: "ScriptedWidgetRuntime",
            dependencies: ["DockCore"],
            swiftSettings: baseSettings
        ),

        /// Reads the system-wide Now Playing state through MediaRemote. Built as a dynamic
        /// library that `SystemServices` runs inside Apple-signed `/usr/bin/perl`, because
        /// MediaRemote ignores other processes since macOS 15.4. Foundation and AppKit only;
        /// it must not depend on the app's other targets.
        .target(
            name: "NowPlayingHelper",
            swiftSettings: baseSettings
        ),

        /// The list of built-in widgets, shared by the app, storage validation, and the
        /// widget docs test.
        .target(
            name: "BuiltInWidgets",
            dependencies: [
                "DockWidgetKit", "ClockWidget", "BatteryWidget", "CalendarWidget", "SystemActivityWidget",
                "WeatherWidget", "NowPlayingWidget", "TimeProgressWidget", "NetworkWidget", "RemindersWidget",
                "TimerWidgets", "StickyNoteWidget", "StocksWidget", "ShortcutsWidget", "AirDropWidget",
                "ScriptedWidgets",
            ],
            path: "Sources/Widgets/BuiltInWidgets",
            swiftSettings: uiSettings
        ),

        // MARK: Shell + App

        /// The floating dock panel itself: window, positioning, auto-hide, item views.
        .target(
            name: "DockShell",
            dependencies: ["DockCore", "DockWidgetKit", "SystemServices"],
            swiftSettings: uiSettings
        ),

        /// The menu bar app that wires everything together.
        .executableTarget(
            name: "OpenDock",
            dependencies: appModules.map { .target(name: $0) } + [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "App/OpenDock",
            swiftSettings: uiSettings
        ),

        // MARK: Tests

        .testTarget(
            name: "DockCoreTests",
            dependencies: ["DockCore"],
            swiftSettings: baseSettings
        ),
        .testTarget(
            name: "SystemServicesTests",
            dependencies: ["DockCore", "SystemServices"],
            resources: [.copy("Fixtures")],
            swiftSettings: baseSettings
        ),
        /// The built-in widgets' settings schemas, that `docs/widgets.md` matches them, and
        /// the presentation helpers of widgets listed here (`@testable import`).
        .testTarget(
            name: "WidgetTests",
            dependencies: ["DockCore", "DockWidgetKit", "BuiltInWidgets", "BatteryWidget", "CalendarWidget"],
            swiftSettings: baseSettings
        ),
        /// Manifest and tile decoding, limits, package loading, and (where JavaScriptCore
        /// exists) the engine against `Examples/Widgets/hello`.
        .testTarget(
            name: "ScriptedWidgetTests",
            dependencies: ["DockCore", "ScriptedWidgetRuntime"],
            swiftSettings: baseSettings
        ),
    ]
)
