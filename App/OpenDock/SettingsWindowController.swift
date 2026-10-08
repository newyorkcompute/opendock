import AppKit
import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// The Settings window: an AppKit toolbar-tab window hosting one SwiftUI pane per tab.
///
/// OpenDock manages this window itself instead of using SwiftUI's `Settings` scene,
/// because macOS 14+ no longer lets an app open that scene programmatically, which
/// a menu-bar app (and the dock's context menu) needs to do.
final class SettingsWindowController: NSWindowController {
    private let tabController = SettingsTabViewController()

    init(
        store: DockStore,
        registry: WidgetRegistry,
        launchAtLogin: LaunchAtLogin,
        windows: AppWindowManager,
        badges: DockBadgeMonitor,
        profiles: ProfileSwitcher,
        hotKeys: GlobalHotKeys
    ) {
        tabController.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let pane = tab.content
                .frame(width: tab.contentSize.width, height: tab.contentSize.height)
                .environment(store)
                .environment(registry)
                .environment(launchAtLogin)
                .environment(windows)
                .environment(badges)
                .environment(profiles)
                .environment(hotKeys)
            let hosting = NSHostingController(rootView: pane)
            hosting.sizingOptions = []
            hosting.preferredContentSize = tab.contentSize
            hosting.title = tab.title

            let item = NSTabViewItem(viewController: hosting)
            item.identifier = tab.rawValue
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.systemImage, accessibilityDescription: tab.title)
            tabController.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabController)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setContentSize(SettingsTab.general.contentSize)
        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unsupported") }

    func show(_ tab: SettingsTab? = nil) {
        if let tab, let index = SettingsTab.allCases.firstIndex(of: tab) {
            tabController.selectedTabViewItemIndex = index
        }
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Resizes the window to each pane's preferred size, keeping the title bar in place.
final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let window = view.window,
            let size = tabViewItem?.viewController?.preferredContentSize,
            size != .zero
        else { return }
        let current = window.frame
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: current.minX, y: current.maxY - frame.height)
        window.setFrame(frame, display: true, animate: window.isVisible)
    }
}
