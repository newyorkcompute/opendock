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

let package = Package(
    name: "OpenDock",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "OpenDock", targets: ["OpenDock"]),
        .library(name: "DockCore", targets: ["DockCore"]),
        .library(name: "DockWidgetKit", targets: ["DockWidgetKit"]),
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

        // MARK: Helpers

        /// Reads the system-wide Now Playing state through MediaRemote. Built as a dynamic
        /// library that `SystemServices` runs inside Apple-signed `/usr/bin/perl`, because
        /// MediaRemote ignores other processes since macOS 15.4. Foundation and AppKit only;
        /// it must not depend on the app's other targets.
        .target(
            name: "NowPlayingHelper",
            swiftSettings: baseSettings
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
            dependencies: [
                "DockCore",
                "DockWidgetKit",
                "DockShell",
                "SystemServices",
                "ClockWidget",
                "BatteryWidget",
                "CalendarWidget",
                "SystemActivityWidget",
                "WeatherWidget",
                "NowPlayingWidget",
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
    ]
)
