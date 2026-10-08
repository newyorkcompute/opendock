import DockCore
import SwiftUI

/// Create, rename, duplicate, reorder, and delete profiles, and choose how to switch them.
struct ProfilesTab: View {
    @Environment(DockStore.self) private var store
    @Environment(ProfileSwitcher.self) private var switcher

    @State private var renaming: DockProfile?
    @State private var draftName = ""
    @State private var deleting: DockProfile?

    var body: some View {
        Form {
            profilesSection
            switchingSection
        }
        .formStyle(.grouped)
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
            Text(profile.items.isEmpty
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
            Text("Each profile is its own set of dock items and widgets. The dock shows the checked one; Dock Items edits it. Settings in General apply to every profile.")
                .settingsFootnote()
        }
    }

    private var switchingSection: some View {
        Section {
            Toggle("Swipe on the dock to switch profiles", isOn: Binding(
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
            Text("Swipe left or right with two fingers on the dock, or hold ⌘ and scroll over it. The shortcuts work in any app and wrap around at the ends of the list. You can also switch from the menu bar.")
                .settingsFootnote()
        }
    }

    // MARK: - Rows

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
