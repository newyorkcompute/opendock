import AppKit
import DockCore

/// The menu on divider items, modeled on the one on the Dock's separators. It opens on
/// click, right-click, and control-click.
extension DockController {
    /// Edges the shell can actually place the dock on. Others show in the menu, disabled.
    static let supportedEdges: Set<DockSettings.Edge> = [.bottom]

    func showDividerMenu(for id: DockItem.ID) {
        let location = NSEvent.mouseLocation
        // Start the menu's tracking loop after the event that asked for it has finished.
        Task { [weak self] in
            guard let self else { return }
            _ = dividerMenu(for: id).popUp(positioning: nil, at: location, in: nil)
        }
    }

    func dividerMenu(for id: DockItem.ID) -> NSMenu {
        let settings = store.settings
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(
            actionMenuItem(settings.autoHide ? "Turn Hiding Off" : "Turn Hiding On") { [store] in
                store.updateSettings { $0.autoHide.toggle() }
            })
        menu.addItem(
            actionMenuItem(settings.hoverEffect ? "Turn Magnification Off" : "Turn Magnification On") { [store] in
                store.updateSettings { $0.hoverEffect.toggle() }
            })

        let positions = NSMenu()
        positions.autoenablesItems = false
        let currentEdge = Self.supportedEdges.contains(settings.edge) ? settings.edge : .bottom
        for edge in [DockSettings.Edge.left, .bottom, .right] {
            let item = actionMenuItem(edge.menuTitle) { [store] in
                store.updateSettings { $0.edge = edge }
            }
            item.state = edge == currentEdge ? .on : .off
            item.isEnabled = Self.supportedEdges.contains(edge)
            positions.addItem(item)
        }
        let position = NSMenuItem(title: "Position on Screen", action: nil, keyEquivalent: "")
        position.submenu = positions
        menu.addItem(position)

        let display = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        display.submenu = displayMenu(current: settings.display)
        menu.addItem(display)

        menu.addItem(
            actionMenuItem("Remove Divider") { [store] in
                store.remove(id: id)
            })
        menu.addItem(.separator())
        menu.addItem(
            actionMenuItem("Dock Settings…") { [weak self] in
                self?.actions.openSettings()
            })
        return menu
    }

    /// The same choices as the Display picker in Settings > General: the main display,
    /// the display with the active menu bar, then each connected display, plus the
    /// chosen one while it's disconnected.
    private func displayMenu(current: DockSettings.Display) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, _ display: DockSettings.Display, checked: Bool) {
            let item = actionMenuItem(title) { [store] in
                store.updateSettings { $0.display = display }
            }
            item.state = checked ? .on : .off
            menu.addItem(item)
        }

        add("Main Display", .main, checked: current == .main)
        add("Display with the Active Menu Bar", .active, checked: current == .active)

        var currentID: String?
        if case let .specific(id, _) = current { currentID = id }
        let screens = NSScreen.screens.map(\.placementScreen).filter { $0.id != nil }
        if !screens.isEmpty || currentID != nil {
            menu.addItem(.separator())
        }
        for screen in screens {
            guard let id = screen.id else { continue }
            add(screen.name, .specific(id: id, name: screen.name), checked: id == currentID)
        }
        if case let .specific(id, name) = current, !screens.contains(where: { $0.id == id }) {
            add("\(name.isEmpty ? "Display" : name) (Disconnected)", current, checked: true)
        }
        return menu
    }

    // MARK: - Right-click and control-click

    /// Sees every right-click and control-click on the dock before SwiftUI does. Records
    /// where it was, for items added from the menu it opens (`menuInsertionIndex`), and
    /// opens this menu for dividers: SwiftUI has no secondary-click gesture, and a
    /// `.contextMenu` would be a second copy of the menu.
    func installContextClickMonitor() {
        guard contextClickMonitor == nil else { return }
        contextClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) {
            [weak self] event in
            guard event.type == .rightMouseDown || event.modifierFlags.contains(.control) else { return event }
            let windowNumber = event.windowNumber
            let handled = MainActor.assumeIsolated { self?.handleContextClick(inWindow: windowNumber) ?? false }
            return handled ? nil : event
        }
    }

    func removeContextClickMonitor() {
        if let contextClickMonitor { NSEvent.removeMonitor(contextClickMonitor) }
        contextClickMonitor = nil
    }

    /// Returns true when the click opened the divider menu and should go no further.
    private func handleContextClick(inWindow windowNumber: Int) -> Bool {
        guard let panel, panel.windowNumber == windowNumber,
            let point = layoutPoint(fromScreen: NSEvent.mouseLocation)
        else { return false }
        shellState.contextClickX = point.x - shellState.geometry.rowCenterX
        guard let id = dividerID(at: point) else { return false }
        showDividerMenu(for: id)
        return true
    }

    /// Where an item added from a context menu on the dock goes: right after `anchor` (the
    /// item whose menu it was), else in the gap nearest the right-click that opened the
    /// dock's background menu.
    func menuInsertionIndex(after anchor: DockItem.ID?) -> Int {
        let items = store.items
        return DockReorder.menuInsertionIndex(
            afterItemAt: anchor.flatMap { id in items.firstIndex { $0.id == id } },
            pointer: shellState.contextClickX.map(Double.init),
            slots: shellState.geometry.restingSlots.map { Double($0.width) },
            limit: items.count
        )
    }

    /// The divider item under `point` (layout coordinates), counting the gaps beside it.
    private func dividerID(at point: CGPoint) -> DockItem.ID? {
        let geometry = shellState.geometry
        let margin = geometry.halfGap
        guard
            let hit = geometry.itemFrames.first(where: { $0.frame.insetBy(dx: -margin, dy: -margin).contains(point) }),
            let id = hit.id.pinnedID,
            store.profile.item(id: id)?.isDivider == true
        else { return nil }
        return id
    }
}

/// A menu item that runs `handler` when chosen.
private func actionMenuItem(_ title: String, handler: @escaping () -> Void) -> NSMenuItem {
    let action = MenuAction(handler)
    let item = NSMenuItem(title: title, action: #selector(MenuAction.fire(_:)), keyEquivalent: "")
    item.target = action
    // `target` is weak; the item keeps the action alive.
    item.representedObject = action
    return item
}

private final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func fire(_ sender: NSMenuItem) { handler() }
}

private extension DockSettings.Edge {
    var menuTitle: String {
        switch self {
        case .left: "Left"
        case .bottom: "Bottom"
        case .right: "Right"
        }
    }
}
