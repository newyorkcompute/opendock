import AppKit
import DockCore
import SwiftUI
import SystemServices

/// The welcome window. It opens by itself once, on a fresh install, and again from the menu
/// bar or Settings. Closing it, however that happens, counts as having seen it.
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private let store: DockStore
    private let launchAtLogin: LaunchAtLogin

    init(store: DockStore, launchAtLogin: LaunchAtLogin) {
        self.store = store
        self.launchAtLogin = launchAtLogin
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: WelcomeView.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = "Welcome to OpenDock"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unsupported") }

    /// Brings the window to the front, starting from the first page unless it's already open.
    func show() {
        guard let window else { return }
        if !window.isVisible {
            window.contentView = makeContent()
            window.center()
        }
        NSApp.activate()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        store.markWelcomeSeen()
    }

    /// Switching to Apple's Dock apps replaces the dock's apps, so it's only offered until
    /// the welcome window has been closed once, before the user has arranged anything.
    private func makeContent() -> NSView {
        let welcome = WelcomeView(
            appleDockApps: store.needsWelcome ? AppleDockApps.read() : [],
            finish: { [weak self] in self?.close() }
        )
        .environment(store)
        .environment(launchAtLogin)

        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .active

        let hosting = NSHostingView(rootView: welcome)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        return background
    }
}

/// Opens the welcome window from inside the Settings window.
struct ShowWelcomeAction {
    private let handler: @MainActor () -> Void

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    static let noop = ShowWelcomeAction {}

    func callAsFunction() {
        handler()
    }
}

extension EnvironmentValues {
    @Entry var showWelcome = ShowWelcomeAction.noop
}
