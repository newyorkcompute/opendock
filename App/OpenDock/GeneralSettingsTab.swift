import AppKit
import DockCore
import SwiftUI

/// Appearance, behavior, startup, and backup settings.
struct GeneralSettingsTab: View {
    @Environment(DockStore.self) private var store
    @Environment(LaunchAtLogin.self) private var launchAtLogin

    @State private var confirmingReset = false

    var body: some View {
        Form {
            appearanceSection
            behaviorSection
            appleDockSection
            startupSection
            backupSection
        }
        .formStyle(.grouped)
        .task {
            launchAtLogin.refresh()
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                launchAtLogin.refresh()
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

            Picker("Material", selection: setting(\.material)) {
                Text("Glass").tag(DockSettings.Material.glass)
                Text("Frosted").tag(DockSettings.Material.frosted)
                Text("Solid").tag(DockSettings.Material.solid)
            }
            .pickerStyle(.segmented)

            LabeledContent("Position") {
                Text("Bottom")
            }

            DisplayPicker()
        } header: {
            Text("Appearance")
        } footer: {
            Text(
                "Liquid Glass requires macOS 26; earlier versions use Frosted. Left and right screen edges are coming soon."
            )
            .settingsFootnote()
        }
    }

    private var behaviorSection: some View {
        Section("Behavior") {
            Toggle("Automatically hide and show the dock", isOn: setting(\.autoHide))

            if store.settings.autoHide {
                LabeledContent("Hide delay") {
                    HStack(spacing: 10) {
                        Slider(value: setting(\.autoHideDelay), in: 0.1 ... 2.0, step: 0.1) {
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

            Toggle("Show indicators for running apps", isOn: setting(\.showRunningIndicators))
            Toggle("Show running apps that aren’t in the dock", isOn: setting(\.showRunningApps))
            Toggle("Animate opening applications", isOn: setting(\.animateOpeningApps))
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
