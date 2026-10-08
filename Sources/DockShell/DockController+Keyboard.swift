import AppKit
import DockCore
import SwiftUI
import SystemServices

/// Controlling the dock from the keyboard (see `DockKeyboardNavigation`). A global shortcut
/// shows the dock and gives it the keyboard. Arrow keys along the row move a selection
/// that's magnified and labeled like the hovered item; Return opens it, Space shows what it
/// has to show (a folder's contents, a widget's popover, an app's menu), Delete offers to
/// remove it, and Escape, or a click anywhere, hands the keyboard back.
///
/// The panel is non-activating, so it takes the keyboard without becoming the active app,
/// the way Spotlight does: the app in front stays in front and gets the keyboard back when
/// the panel orders out.
extension DockController {
    private typealias Navigation = DockKeyboardNavigation<DockRowItemID>

    /// Starts keyboard control, or ends it if it's on, so the shortcut that starts it also
    /// gets out of it.
    public func toggleKeyboardNavigation() {
        if keyboard.isActive {
            endKeyboardNavigation()
        } else {
            beginKeyboardNavigation()
        }
    }

    func beginKeyboardNavigation() {
        guard let panel, !keyboard.isActive else { return }
        cancelScheduledHide()
        if isOnFullScreenSpace {
            // The dock isn't on this Space; it joins it the way the edge hold brings it in,
            // unless the setting says it never should.
            guard store.settings.revealInFullScreen else { return }
            revealOverFullScreen()
        } else if !shellState.isVisible {
            reveal()
        }
        installKeyboardMonitors()
        panel.makeKey()
        apply(keyboard.begin(items: keyboardRowItems, preferring: shellState.hoveredItemID))
    }

    /// Hands the keyboard back. With auto-hide on, the dock goes away too, unless the pointer
    /// is on it, in which case the pointer carries on from where the selection was.
    func endKeyboardNavigation() {
        guard keyboard.isActive else { return }
        let selected = keyboard.selectedID
        _ = keyboard.end()
        removeKeyboardMonitors()
        shellState.keyboardSelection = nil
        if pointerIsOverDock {
            releaseKeyboard()
            pointerMoved(to: layoutPoint(fromScreen: NSEvent.mouseLocation))
            return
        }
        // Settle the row back from the selection, not from wherever the pointer last was.
        if let selected, let center = restingCenter(of: selected) { shellState.pointer = center }
        if hidesWhenPointerLeaves { hide() }
        // Hiding orders the panel out, which returns the keyboard by itself.
        guard shellState.isVisible else { return }
        releaseKeyboard()
        shellState.hoveredItemID = nil
        withAnimation(.dockDemagnify) { shellState.magnification = 0 }
    }

    /// The pointer came to rest on `id`: the selection follows it, quietly.
    func keyboardSelectionFollowedPointer(to id: DockRowItemID) {
        if case .selected = keyboard.select(id, in: keyboardRowItems) {
            shellState.keyboardSelection = id
        }
    }

    /// The row's items changed (one was removed, an app quit, the profile switched).
    func keyboardRowChanged() {
        guard keyboard.isActive else { return }
        apply(keyboard.itemsChanged(keyboardRowItems))
    }

    /// A popover or menu opened for the selection has closed: the selection takes the
    /// keyboard back, unless the pointer has moved onto the dock meanwhile.
    func keyboardInteractionEnded() {
        panel?.makeKey()
        if pointerIsOverDock {
            pointerMoved(to: layoutPoint(fromScreen: NSEvent.mouseLocation))
        } else {
            presentKeyboardSelection()
        }
    }

    /// Shows the selection the way the hovered item is shown: labeled, and magnified (the
    /// layout magnifies around the keyboard's selection while the pointer is off the dock).
    func presentKeyboardSelection() {
        shellState.hoveredItemID = keyboard.selectedID
        guard keyboard.selectedID != nil, shellState.magnification != 1 else { return }
        withAnimation(.dockMagnify) { shellState.magnification = 1 }
    }

    /// The items the keyboard can select, in row order: everything that gets a label, less
    /// the items the layout found nothing to show for (see `DockGeometry.hiddenItemIDs`).
    private var keyboardRowItems: [DockRowItemID] {
        let hidden = shellState.geometry.hiddenItemIDs
        return
            (store.items.filter { !$0.isSpacer && !$0.isDivider }.map { DockRowItemID.pinned($0.id) }
            + runningSection.map { .running($0.id) } + recentSection.map { .recent($0.id) }
            + (store.showsTrash ? [.trash] : []))
            .filter { !hidden.contains($0) }
    }

    /// The app `id` stands for, when it's one of the apps after the pinned items.
    private func sectionApp(for id: DockRowItemID) -> AppItem? {
        switch id {
        case .pinned, .trash: return nil
        case let .running(appID): return runningSection.first { $0.id == appID }?.app
        case let .recent(appID): return recentSection.first { $0.id == appID }?.app
        }
    }

    // MARK: - Effects

    private func apply(_ effect: Navigation.Effect) {
        switch effect {
        case let .selected(id, position, count):
            shellState.keyboardSelection = id
            presentKeyboardSelection()
            if let name = displayName(for: id) {
                announce("\(name), \(position) of \(count)")
            }
        case let .activate(id):
            activate(id)
        case let .openSecondary(id):
            openSecondary(id)
        case let .offerRemoval(id):
            offerRemoval(id)
        case .ended:
            endKeyboardNavigation()
        case .none:
            shellState.keyboardSelection = keyboard.selectedID
            presentKeyboardSelection()
        }
    }

    /// Return: opens an app or folder, which takes the keyboard with it, so keyboard control
    /// ends first. A widget has nothing to open but its popover.
    private func activate(_ id: DockRowItemID) {
        switch id {
        case let .pinned(itemID):
            switch store.profile.item(id: itemID)?.kind {
            case let .app(app):
                endKeyboardNavigation()
                open(app)
            case let .folder(folder):
                endKeyboardNavigation()
                AppLauncher.open(folder)
            case .widget:
                openSecondary(id)
            case .spacer, .divider, nil:
                break
            }
        case .running, .recent:
            guard let app = sectionApp(for: id) else { return }
            endKeyboardNavigation()
            open(app)
        case .trash:
            endKeyboardNavigation()
            openTrash()
        }
    }

    /// Space: a folder's contents or a widget's popover, which the item's view presents, or
    /// an app's menu, with its windows, or the Trash's menu.
    private func openSecondary(_ id: DockRowItemID) {
        switch id {
        case let .pinned(itemID):
            switch store.profile.item(id: itemID)?.kind {
            case let .app(app):
                showAppMenu(for: app, id: id, at: menuLocation(for: id))
            case .folder, .widget:
                popoverRequestSerial += 1
                shellState.popoverRequest = .init(item: itemID, serial: popoverRequestSerial)
            case .spacer, .divider, nil:
                break
            }
        case .running, .recent:
            guard let app = sectionApp(for: id) else { return }
            showAppMenu(for: app, id: id, at: menuLocation(for: id))
        case .trash:
            showTrashMenu(at: menuLocation(for: id))
        }
    }

    /// Delete: a menu over the item with Remove from Dock, so a slip of the finger doesn't
    /// remove anything. Running apps that aren't in the dock have nothing to remove, and
    /// the Trash is taken away in Settings.
    private func offerRemoval(_ id: DockRowItemID) {
        guard let itemID = id.pinnedID, let name = displayName(for: id) else { return }
        let location = menuLocation(for: id)
        // Start the menu's tracking loop after the key press that asked for it has finished.
        Task { [store] in
            let menu = NSMenu()
            menu.autoenablesItems = false
            let title = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            menu.addItem(.separator())
            menu.addItem(actionMenuItem("Remove from Dock") { store.remove(id: itemID) })
            _ = menu.popUp(positioning: nil, at: location, in: nil)
        }
    }

    /// Where a menu for `id` opens: just past the item on the side away from the screen
    /// edge, where its label is.
    private func menuLocation(for id: DockRowItemID) -> NSPoint {
        guard let panel, let hostingView,
            let frame = shellState.geometry.itemFrames.first(where: { $0.id == id })?.frame
        else { return NSEvent.mouseLocation }
        let origin = shellState.geometry.containerOrigin
        var rect = frame.offsetBy(dx: origin.x, dy: origin.y)
        if !hostingView.isFlipped { rect.origin.y = hostingView.bounds.height - rect.maxY }
        let onScreen = panel.convertToScreen(hostingView.convert(rect, to: nil))
        let gap = DockRowMetrics.labelGap
        switch shellState.geometry.edge {
        case .bottom: return NSPoint(x: onScreen.minX, y: onScreen.maxY + gap)
        case .left: return NSPoint(x: onScreen.maxX + gap, y: onScreen.maxY)
        case .right: return NSPoint(x: onScreen.minX - gap, y: onScreen.maxY)
        }
    }

    private func displayName(for id: DockRowItemID) -> String? {
        switch id {
        case let .pinned(itemID):
            switch store.profile.item(id: itemID)?.kind {
            case let .app(app): return app.displayName
            case let .folder(folder): return folder.displayName
            case let .widget(instance): return registry.displayName(for: instance)
            case .spacer, .divider, nil: return nil
            }
        case .running, .recent:
            return sectionApp(for: id)?.displayName
        case .trash:
            return "Trash"
        }
    }

    /// Tells VoiceOver what's selected. Posted on the app, since the dock isn't a focused
    /// window in the usual sense.
    private func announce(_ text: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }

    // MARK: - Keys

    /// Sees key presses while the keyboard controls the dock. Handled keys go no further;
    /// the rest (and anything with ⌘ held) pass through.
    private func handleKeyDown(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        guard keyboard.isActive, !shellState.isInteracting, !flags.contains(.command) else { return false }
        let edge = store.settings.edge
        let key: Navigation.Key?
        switch keyCode {
        case 123: key = .init(arrow: .left, edge: edge)
        case 124: key = .init(arrow: .right, edge: edge)
        case 125: key = .init(arrow: .down, edge: edge)
        case 126: key = .init(arrow: .up, edge: edge)
        case 115: key = .first // Home
        case 119: key = .last // End
        case 36, 76: key = .activate // Return, Enter
        case 49: key = .secondary // Space
        case 51, 117: key = .remove // Delete, Forward Delete
        case 53: key = .escape
        default: return false
        }
        // An arrow across the row is still the dock's: it just does nothing.
        guard let key else { return true }
        apply(keyboard.handle(key, items: keyboardRowItems))
        return true
    }

    private func installKeyboardMonitors() {
        guard keyboardMonitors.isEmpty, let panel else { return }
        let keys = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            let handled = MainActor.assumeIsolated {
                self?.handleKeyDown(keyCode: keyCode, flags: NSEvent.ModifierFlags(rawValue: flags)) ?? false
            }
            return handled ? nil : event
        }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let localClicks = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            let windowNumber = event.windowNumber
            MainActor.assumeIsolated { self?.dockClicked(inWindow: windowNumber) }
            return event
        }
        let globalClicks = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            MainActor.assumeIsolated { self?.endKeyboardNavigation() }
        }
        keyboardMonitors = [keys, localClicks, globalClicks].compactMap { $0 }
        keyboardObservers = [
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.panelResignedKey() }
            }
        ]
    }

    func removeKeyboardMonitors() {
        keyboardMonitors.forEach(NSEvent.removeMonitor)
        keyboardMonitors = []
        keyboardObservers.forEach(NotificationCenter.default.removeObserver)
        keyboardObservers = []
    }

    /// A click on the dock itself: the pointer takes over. Clicks in the dock's popovers
    /// and other windows of the app are theirs to handle (the panel resigning key covers
    /// the Settings window).
    private func dockClicked(inWindow windowNumber: Int) {
        guard let panel, panel.windowNumber == windowNumber else { return }
        // After the click has been delivered, so it still lands on what it was aimed at.
        Task { [weak self] in self?.endKeyboardNavigation() }
    }

    /// The keyboard went elsewhere. The dock's own popovers and menus borrow it for a
    /// moment (`keyboardInteractionEnded` takes it back); anything else, like another app
    /// or the Settings window coming to the front, means the user has moved on.
    private func panelResignedKey() {
        // Checked after the hand-off has settled, so the new key window is known.
        Task { [weak self] in
            guard let self, keyboard.isActive, !shellState.isInteracting, panel?.isKeyWindow == false else { return }
            endKeyboardNavigation()
        }
    }

    /// Gives the keyboard back to the app in front: ordering the panel out is what does it.
    /// Ordered straight back in, it's never seen to go.
    private func releaseKeyboard() {
        guard let panel, panel.isKeyWindow else { return }
        panel.orderOut(nil)
        if shellState.isVisible { panel.orderFrontRegardless() }
    }
}
