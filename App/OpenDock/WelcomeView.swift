import AppKit
import DockCore
import SwiftUI

/// The welcome window's pages: where OpenDock lives, a few opt-in choices, and which
/// permissions features ask for.
struct WelcomeView: View {
    static let size = CGSize(width: 500, height: 540)

    /// Apple's Dock apps, offered in place of the starter apps. Empty to not offer them.
    let appleDockApps: [URL]
    let finish: () -> Void

    @Environment(DockStore.self) private var store
    @Environment(LaunchAtLogin.self) private var launchAtLogin

    @State private var page = Page.dock
    /// The apps the dock had before switching to Apple's Dock apps, to switch back to.
    @State private var replacedApps: [URL]?

    private enum Page: Int, CaseIterable {
        case dock
        case setup
        case permissions
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case .dock: dockPage
                case .setup: setupPage
                case .permissions: permissionsPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity)

            footer
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: Self.size.width, height: Self.size.height)
        .task {
            launchAtLogin.refresh()
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                launchAtLogin.refresh()
            }
        }
    }

    // MARK: - Pages

    private var dockPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                title("Welcome to OpenDock")
                subtitle(
                    "Your new dock is at the bottom of the screen. OpenDock has no Dock icon of its own: it lives in the menu bar."
                )
            }
            WelcomeCard {
                WelcomeRow(
                    systemImage: "menubar.rectangle",
                    title: "Find it in the menu bar",
                    text: "Click the dock icon in the menu bar for Settings, profiles, and Quit."
                )
                WelcomeRow(
                    systemImage: "plus.square.on.square",
                    title: "Add what you use",
                    text:
                        "Drop apps, folders, and files from Finder onto the dock, or right-click the dock to add widgets, spacers, and dividers."
                )
                WelcomeRow(
                    systemImage: "hand.draw",
                    title: "Arrange it",
                    text: "Drag items to reorder them. Right-click an item to remove it."
                )
            }
        }
    }

    private var setupPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                title("Set Up Your Dock")
                subtitle("All optional. You can change these later in Settings.")
            }
            WelcomeCard {
                if appleDockApps.count > 1 {
                    WelcomeRow(
                        systemImage: "square.and.arrow.down",
                        title: "Use the apps from Apple’s Dock",
                        text:
                            "OpenDock starts with a few common apps. Use the \(appleDockApps.count) apps in Apple’s Dock instead."
                    ) {
                        WelcomeToggle("Use the apps from Apple’s Dock", isOn: useAppleDockApps)
                    }
                }
                WelcomeRow(
                    systemImage: "eye.slash",
                    title: "Hide Apple’s Dock",
                    text:
                        "Keeps Apple’s Dock out of the way while OpenDock runs. Your Dock settings come back when you quit OpenDock or turn this off."
                ) {
                    WelcomeToggle("Hide Apple’s Dock", isOn: hideAppleDock)
                }
                WelcomeRow(
                    systemImage: "power",
                    title: "Open at login",
                    text: launchAtLoginText
                ) {
                    WelcomeToggle("Open OpenDock at login", isOn: openAtLogin)
                        .disabled(!launchAtLogin.isAvailable)
                }
                if launchAtLogin.requiresApproval {
                    Button("Open Login Items…") { launchAtLogin.openSystemSettings() }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private var permissionsPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                title("Permissions")
                subtitle(
                    "Some features need your permission, and each asks only when it needs it. You can change your answer anytime in System Settings > Privacy & Security."
                )
            }
            WelcomeCard {
                WelcomeRow(
                    systemImage: "calendar",
                    title: "Calendars",
                    text:
                        "The Calendar widget asks to read your events so it can show what’s next. On a new install, it waits until you close this window."
                )
                WelcomeRow(
                    systemImage: "macwindow.on.rectangle",
                    title: "Accessibility",
                    text:
                        "Listing an app’s windows in its menu and click-to-minimize need Accessibility access. OpenDock asks when you first use one of them."
                )
            }
            Text("You can open this guide again from the OpenDock menu in the menu bar.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.title.weight(.semibold))
    }

    private func subtitle(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var launchAtLoginText: String {
        if !launchAtLogin.isAvailable { return "Available when running OpenDock.app." }
        if launchAtLogin.requiresApproval { return "Allow OpenDock in System Settings to finish turning this on." }
        return launchAtLogin.errorMessage ?? "Start OpenDock when you log in to your Mac."
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(Page.allCases, id: \.self) { dot in
                    Circle()
                        .fill(Color.primary.opacity(dot == page ? 0.8 : 0.25))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Page \(page.rawValue + 1) of \(Page.allCases.count)")

            Spacer()

            if let previous = Page(rawValue: page.rawValue - 1) {
                Button("Back") { go(to: previous) }
                    .modifier(WelcomeButtonStyle(prominent: false))
            }
            if let next = Page(rawValue: page.rawValue + 1) {
                Button("Continue") { go(to: next) }
                    .keyboardShortcut(.defaultAction)
                    .modifier(WelcomeButtonStyle(prominent: true))
            } else {
                Button("Done", action: finish)
                    .keyboardShortcut(.defaultAction)
                    .modifier(WelcomeButtonStyle(prominent: true))
            }
        }
        .controlSize(.large)
    }

    private func go(to destination: Page) {
        withAnimation(.easeInOut(duration: 0.2)) { page = destination }
    }

    // MARK: - Bindings

    private var useAppleDockApps: Binding<Bool> {
        Binding(
            get: { replacedApps != nil },
            set: { use in
                if use, replacedApps == nil {
                    replacedApps = store.items.compactMap(\.appItem?.url)
                    store.replaceApps(with: appleDockApps)
                } else if !use, let previous = replacedApps {
                    store.replaceApps(with: previous)
                    replacedApps = nil
                }
            }
        )
    }

    private var hideAppleDock: Binding<Bool> {
        Binding(
            get: { store.settings.hideAppleDock },
            set: { value in store.updateSettings { $0.hideAppleDock = value } }
        )
    }

    private var openAtLogin: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.isEnabled = $0 }
        )
    }
}

// MARK: - Building blocks

/// A rounded group of rows: Liquid Glass on macOS 26, frosted before.
private struct WelcomeCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let stack = VStack(alignment: .leading, spacing: 16) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        if #available(macOS 26.0, *) {
            stack.glassEffect(.regular, in: shape)
        } else {
            stack.background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        }
    }
}

/// A symbol, a title, a line or two of explanation, and an optional control on the right.
private struct WelcomeRow<Accessory: View>: View {
    let systemImage: String
    let title: String
    let text: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
    }
}

extension WelcomeRow where Accessory == EmptyView {
    init(systemImage: String, title: String, text: String) {
        self.init(systemImage: systemImage, title: title, text: text) { EmptyView() }
    }
}

/// A switch whose label is only read by VoiceOver; the row shows the title.
private struct WelcomeToggle: View {
    let label: String
    @Binding var isOn: Bool

    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        _isOn = isOn
    }

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
    }
}

/// Liquid Glass buttons on macOS 26, standard ones before.
private struct WelcomeButtonStyle: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content
        }
    }
}
