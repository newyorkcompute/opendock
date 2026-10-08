import AppKit
import DockCore
import SwiftUI
import SystemServices

/// Create, rename, duplicate, reorder, and delete profiles, and choose how to switch them.
struct ProfilesTab: View {
    @Environment(DockStore.self) private var store
    @Environment(ProfileSwitcher.self) private var switcher
    @Environment(FocusModeMonitor.self) private var focus

    @State private var renaming: DockProfile?
    @State private var draftName = ""
    @State private var deleting: DockProfile?

    var body: some View {
        Form {
            profilesSection
            switchingSection
            focusSection
        }
        .formStyle(.grouped)
        .task {
            focus.refresh()
            // Coming back from System Settings, where Full Disk Access may have just been allowed.
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                focus.refresh()
            }
        }
        .alert("Rename Profile", isPresented: isPresented($renaming), presenting: renaming) { profile in
            TextField("Name", text: $draftName)
            Button("Rename") { store.renameProfile(profile.id, to: draftName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: isPresented($deleting),
            presenting: deleting
        ) { profile in
            Button("Delete", role: .destructive) { switcher.delete(profile.id) }
            Button("Cancel", role: .cancel) {}
        } message: { profile in
            Text(
                profile.items.isEmpty
                    ? "This profile is empty."
                    : "Its \(itemCount(profile)) will be removed. Other profiles aren’t affected.")
        }
    }

    // MARK: - Sections

    private var profilesSection: some View {
        Section {
            ForEach(Array(store.profiles.enumerated()), id: \.element.id) { index, profile in
                row(for: profile, at: index)
            }
            HStack {
                Button("New Profile") { switcher.create() }
                Button("Duplicate") { switcher.duplicate(store.activeProfileID) }
                    .help("Copy the profile the dock is showing")
            }
        } header: {
            Text("Profiles")
        } footer: {
            Text(
                "Each profile is its own set of dock items and widgets. The dock shows the checked one; Dock Items edits it. Settings in General apply to every profile."
            )
            .settingsFootnote()
        }
    }

    private var switchingSection: some View {
        Section {
            Toggle(
                "Swipe on the dock to switch profiles",
                isOn: Binding(
                    get: { store.settings.switchProfilesByScrolling },
                    set: { value in store.updateSettings { $0.switchProfilesByScrolling = value } }
                ))
            LabeledContent("Next profile") {
                HotKeyRecorder(hotKey: hotKey(\.nextProfileHotKey))
            }
            LabeledContent("Previous profile") {
                HotKeyRecorder(hotKey: hotKey(\.previousProfileHotKey))
            }
        } header: {
            Text("Switching")
        } footer: {
            Text(
                "Swipe left or right with two fingers on the dock, or hold ⌘ and scroll over it. The shortcuts work in any app and wrap around at the ends of the list. You can also switch from the menu bar."
            )
            .settingsFootnote()
        }
    }

    private var focusSection: some View {
        Section {
            switch focus.access {
            case .granted:
                if focus.modes.isEmpty {
                    Text("No Focus modes are set up on this Mac.")
                        .foregroundStyle(.secondary)
                }
                ForEach(focus.modes) { mode in
                    focusRow(for: mode)
                }
                Picker(
                    "When Focus turns off",
                    selection: Binding(
                        get: { store.settings.focusRules.whenFocusEnds },
                        set: { value in store.updateSettings { $0.focusRules.whenFocusEnds = value } }
                    )
                ) {
                    Text("Return to the previous profile").tag(FocusProfileRules.FocusEnd.returnToPrevious)
                    Text("Keep the Focus’s profile").tag(FocusProfileRules.FocusEnd.stay)
                }
            case .denied:
                LabeledContent {
                    Button("Open System Settings…") { focus.openAccessSettings() }
                } label: {
                    Label(
                        "Allow OpenDock Full Disk Access to see which Focus is on.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .symbolRenderingMode(.multicolor)
                }
            case .unavailable:
                Text("Focus modes aren’t available on this Mac.")
                    .foregroundStyle(.secondary)
            case .unknown:
                ProgressView()
                    .controlSize(.small)
            }
        } header: {
            Text("Focus")
        } footer: {
            Text(focusFootnote)
                .settingsFootnote()
        }
    }

    private var focusFootnote: String {
        switch focus.access {
        case .denied:
            "macOS keeps which Focus is on in a protected part of your Library folder, which OpenDock can only read with Full Disk Access. Add OpenDock under System Settings > Privacy & Security > Full Disk Access, then quit and reopen OpenDock. It only reads your Focus settings and never changes them."
        default:
            "When a Focus turns on, the dock switches to its profile. A Focus set to “Don’t change” leaves the dock as it is. If you pick another profile yourself while a Focus is on, it stays when the Focus ends. Focus modes are set up in System Settings > Focus."
        }
    }

    // MARK: - Rows

    private func focusRow(for mode: FocusMode) -> some View {
        Picker(selection: focusProfile(for: mode.id)) {
            Text("Don’t change").tag(DockProfile.ID?.none)
            ForEach(store.profiles) { profile in
                Text(profile.name).tag(Optional(profile.id))
            }
        } label: {
            HStack(spacing: 6) {
                Label(mode.name, systemImage: mode.symbolName ?? "moon.fill")
                if mode.id == focus.activeModeID {
                    Text("On")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                        .accessibilityLabel("\(mode.name) is on")
                }
            }
        }
    }

    private func row(for profile: DockProfile, at index: Int) -> some View {
        let isActive = profile.id == store.activeProfileID
        let accessibilityName: String = isActive ? "\(profile.name), showing" : "Show \(profile.name)"
        return HStack(spacing: 10) {
            Button {
                switcher.select(profile.id)
            } label: {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.borderless)
            .help(isActive ? "The dock is showing this profile" : "Show this profile in the dock")
            .accessibilityLabel(accessibilityName)

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                Text(profile.items.isEmpty ? "Empty" : itemCount(profile))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                actions(for: profile, at: index)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Profile Actions")
        }
        .contentShape(Rectangle())
        .contextMenu { actions(for: profile, at: index) }
    }

    @ViewBuilder
    private func actions(for profile: DockProfile, at index: Int) -> some View {
        Button("Show in Dock") { switcher.select(profile.id) }
            .disabled(profile.id == store.activeProfileID)
        Button("Rename…") {
            draftName = profile.name
            renaming = profile
        }
        Button("Duplicate") { switcher.duplicate(profile.id) }
        Divider()
        Button("Move Up") { store.moveProfile(profile.id, by: -1) }
            .disabled(index == 0)
        Button("Move Down") { store.moveProfile(profile.id, by: 1) }
            .disabled(index == store.profiles.count - 1)
        Divider()
        Button("Delete…", role: .destructive) { deleting = profile }
            .disabled(store.profiles.count == 1)
    }

    // MARK: - Helpers

    private func itemCount(_ profile: DockProfile) -> String {
        profile.items.count == 1 ? "1 item" : "\(profile.items.count) items"
    }

    /// A binding to the profile a Focus mode shows: nil for "Don't change", which is also what
    /// a deleted profile reads as.
    private func focusProfile(for mode: String) -> Binding<DockProfile.ID?> {
        Binding(
            get: {
                guard let id = store.settings.focusRules.profile(for: mode), store.document.profile(id: id) != nil
                else { return nil }
                return id
            },
            set: { value in store.setFocusProfile(value, for: mode) }
        )
    }

    /// A binding to one of the profile shortcuts. A shortcut can only do one thing, so
    /// giving it to one action takes it from the other.
    private func hotKey(_ keyPath: WritableKeyPath<DockSettings, HotKey?>) -> Binding<HotKey?> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { value in
                store.updateSettings { settings in
                    settings[keyPath: keyPath] = value
                    guard let value else { return }
                    for other in [\DockSettings.nextProfileHotKey, \DockSettings.previousProfileHotKey]
                    where other != keyPath && settings[keyPath: other] == value {
                        settings[keyPath: other] = nil
                    }
                }
            }
        )
    }

    private func isPresented<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue != nil },
            set: { if !$0 { value.wrappedValue = nil } }
        )
    }
}
