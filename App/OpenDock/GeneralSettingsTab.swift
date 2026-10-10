import AppKit
import DockCore
import SwiftUI
import SystemServices

/// Appearance, behavior, apps, keyboard, Accessibility, Apple's Dock, startup, and backup
/// settings.
struct GeneralSettingsTab: View {
    @Environment(DockStore.self) private var store
    @Environment(LaunchAtLogin.self) private var launchAtLogin
    @Environment(AccessibilityPermission.self) private var accessibility

    @State private var confirmingReset = false

    var body: some View {
        Form {
            appearanceSection
            behaviorSection
            appsSection
            keyboardSection
            accessibilitySection
            appleDockSection
            startupSection
            backupSection
        }
        .formStyle(.grouped)
        .task {
            launchAtLogin.refresh()
            accessibility.refresh()
            // Coming back from System Settings, where either may have just been allowed.
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                launchAtLogin.refresh()
                accessibility.refresh()
            }
        }
        .alert("Reset OpenDock to its defaults?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { store.resetToFirstRun() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "All your profiles, dock items, widgets, and settings will be replaced with the starter layout. Export your layout first if you want to keep it."
            )
        }
    }

    // MARK: - Sections

    /// How the dock looks: size, magnification, material, and where it is.
    private var appearanceSection: some View {
        Section {
            LabeledContent("Icon size") {
                HStack(spacing: 10) {
                    Slider(value: setting(\.iconSize), in: DockSettings.iconSizeRange, step: 4) {
                        Text("Icon size")
                    } minimumValueLabel: {
                        Image(systemName: "app").imageScale(.small)
                    } maximumValueLabel: {
                        Image(systemName: "app").imageScale(.large)
                    }
                    .labelsHidden()
                    Text("\(Int(store.settings.iconSize)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }

            Toggle("Magnification", isOn: setting(\.hoverEffect))

            if store.settings.hoverEffect {
                LabeledContent("Magnified size") {
                    HStack(spacing: 10) {
                        Slider(value: setting(\.magnification), in: DockSettings.magnificationRange, step: 0.05) {
                            Text("Magnified size")
                        } minimumValueLabel: {
                            Text("Small").font(.caption)
                        } maximumValueLabel: {
                            Text("Large").font(.caption)
                        }
                        .labelsHidden()
                        Text("\(Int((store.settings.iconSize * store.settings.magnification).rounded())) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Picker("Material", selection: setting(\.material)) {
                Text("Glass").tag(DockSettings.Material.glass)
                Text("Frosted").tag(DockSettings.Material.frosted)
                Text("Solid").tag(DockSettings.Material.solid)
            }
            .pickerStyle(.segmented)

            Picker("Position on screen", selection: setting(\.edge)) {
                Text("Left").tag(DockSettings.Edge.left)
                Text("Bottom").tag(DockSettings.Edge.bottom)
                Text("Right").tag(DockSettings.Edge.right)
            }
            .pickerStyle(.segmented)

            DisplayPicker()
        } header: {
            Text("Appearance")
        } footer: {
            Text("Liquid Glass requires macOS 26; earlier versions use Frosted.")
                .settingsFootnote()
        }
    }

    /// When the dock shows and hides, and what clicks and launches do.
    private var behaviorSection: some View {
        Section {
            Toggle("Automatically hide and show the dock", isOn: setting(\.autoHide))

            if store.settings.autoHide {
                LabeledContent("Hide delay") {
                    HStack(spacing: 10) {
                        Slider(value: setting(\.autoHideDelay), in: DockSettings.autoHideDelayRange, step: 0.1) {
                            Text("Hide delay")
                        }
                        .labelsHidden()
                        Text("\(store.settings.autoHideDelay.formatted(.number.precision(.fractionLength(1)))) s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Toggle("Show the dock in full-screen apps", isOn: setting(\.revealInFullScreen))
            Toggle("Animate opening applications", isOn: setting(\.animateOpeningApps))
            Toggle(
                "Click the active app’s icon to minimize its windows",
                isOn: Binding(
                    get: { store.settings.clickToMinimize },
                    set: { enabled in
                        store.updateSettings { $0.clickToMinimize = enabled }
                        if enabled { accessibility.request() }
                    }
                )
            )
        } header: {
            Text("Behavior")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if store.settings.revealInFullScreen {
                    Text(
                        "In a full-screen app, hold the pointer at the \(store.settings.edge.screenEdgeName) edge of the screen for a moment to show the dock. It hides again when the pointer leaves."
                    )
                }
                if store.settings.clickToMinimize {
                    Text("Clicking the icon again restores the windows. Needs Accessibility access.")
                }
            }
            .settingsFootnote()
        }
    }

    /// What the dock shows about apps: indicators, the running and recent sections, badges.
    private var appsSection: some View {
        Section {
            Toggle("Show indicators for running apps", isOn: setting(\.showRunningIndicators))
            Toggle("Show running apps that aren’t in the dock", isOn: setting(\.showRunningApps))
            Toggle("Show recent apps that aren’t in the dock", isOn: setting(\.showRecentApps))

            if store.settings.showRecentApps {
                Picker("Number of recent apps", selection: setting(\.recentAppsCount)) {
                    ForEach(DockSettings.recentAppsCountRange, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
            }

            Toggle(
                "Show badges on app icons",
                isOn: Binding(
                    get: { store.settings.showBadges },
                    set: { enabled in
                        store.updateSettings { $0.showBadges = enabled }
                        if enabled { accessibility.request() }
                    }
                )
            )
        } header: {
            Text("Apps")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if store.settings.showRecentApps {
                    Text(
                        "Recent apps are the ones you switched to last that aren’t in the dock and aren’t running. They’re only noted while this is on, and are kept across relaunches."
                    )
                }
                if store.settings.showBadges {
                    Text(
                        "Unread counts and other badges are read from Apple’s Dock, which needs Accessibility access. Apps show their badges while they’re running or kept in Apple’s Dock."
                    )
                }
            }
            .settingsFootnote()
        }
    }

    private var keyboardSection: some View {
        Section {
            LabeledContent("Control the dock") {
                HotKeyRecorder(
                    hotKey: Binding(
                        get: { store.settings.keyboardNavigationHotKey },
                        set: { value in store.updateSettings { $0.setHotKey(value, for: \.keyboardNavigationHotKey) } }
                    ))
            }
        } header: {
            Text("Keyboard")
        } footer: {
            Text(
                "The shortcut shows the dock and selects an item. Use the arrow keys to move along the dock, Return to open, Space to browse a folder or open a widget, Delete to remove an item, and Escape when you’re done."
            )
            .settingsFootnote()
        }
    }

    /// The one permission several features share, shown in one place.
    private var accessibilitySection: some View {
        Section {
            LabeledContent("Accessibility access") {
                if accessibility.isGranted {
                    Text("Allowed").foregroundStyle(.secondary)
                } else {
                    Button("Allow…") { accessibility.request() }
                }
            }

            if !accessibility.isGranted,
                store.settings.clickToMinimize || store.settings.showBadges || store.settings.showMinimizedWindows
            {
                Label(
                    "Badges, minimized windows, and click-to-minimize stay off until OpenDock is allowed.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .symbolRenderingMode(.multicolor)
            }
        } header: {
            Text("Accessibility")
        } footer: {
            Text(
                "OpenDock uses Accessibility access to list an app’s windows in its menu and bring one to the front, to minimize and restore them, to show minimized windows in the dock, and to read badges from Apple’s Dock. It doesn’t read what’s in your windows. Thumbnails of minimized windows are separate: they need Screen Recording, offered in Dock Items."
            )
            .settingsFootnote()
        }
    }

    private var appleDockSection: some View {
        Section {
            Toggle("Hide Apple’s Dock while OpenDock runs", isOn: setting(\.hideAppleDock))
        } header: {
            Text("Apple’s Dock")
        } footer: {
            Text(
                "Turns on auto-hide for Apple’s Dock with a long delay so it stays out of the way. Your Dock settings are put back when you quit OpenDock or turn this off."
            )
            .settingsFootnote()
        }
    }

    private var startupSection: some View {
        Section {
            Toggle(
                "Open OpenDock at login",
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.isEnabled = $0 }
                )
            )
            .disabled(!launchAtLogin.isAvailable)

            if launchAtLogin.requiresApproval {
                LabeledContent {
                    Button("Open Login Items…") { launchAtLogin.openSystemSettings() }
                } label: {
                    Label(
                        "Allow OpenDock in System Settings to finish turning this on.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .symbolRenderingMode(.multicolor)
                }
            }

            if let message = launchAtLogin.errorMessage {
                Label(message, systemImage: "xmark.octagon.fill")
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Startup")
        } footer: {
            if !launchAtLogin.isAvailable {
                Text("Launch at login is available when running OpenDock.app.")
                    .settingsFootnote()
            }
        }
    }

    private var backupSection: some View {
        Section {
            LabeledContent("Layout") {
                HStack {
                    Button("Export…") { BackupActions.exportLayout(from: store) }
                    Button("Import…") { BackupActions.importLayout(into: store) }
                }
            }
            LabeledContent("Defaults") {
                Button("Reset to Defaults…", role: .destructive) { confirmingReset = true }
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("A layout file contains all your profiles with their dock items and widgets, plus your settings.")
                .settingsFootnote()
        }
    }

    // MARK: - Bindings

    /// A binding to one setting that writes through `DockStore.updateSettings`.
    private func setting<Value>(_ keyPath: WritableKeyPath<DockSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { value in store.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }
}

extension View {
    /// Style for explanatory text under a settings section.
    func settingsFootnote() -> some View {
        font(.footnote).foregroundStyle(.secondary)
    }
}

extension DockSettings.Edge {
    /// The edge as named in a sentence: "the bottom edge of the screen".
    fileprivate var screenEdgeName: String {
        switch self {
        case .bottom: "bottom"
        case .left: "left"
        case .right: "right"
        }
    }
}
