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

        menu.addItem(ActionMenuItem(settings.autoHide ? "Turn Hiding Off" : "Turn Hiding On") { [store] in
            store.updateSettings { $0.autoHide.toggle() }
        })
        menu.addItem(ActionMenuItem(settings.hoverEffect ? "Turn Magnification Off" : "Turn Magnification On") { [store] in
            store.updateSettings { $0.hoverEffect.toggle() }
        })

        let positions = NSMenu()
        positions.autoenablesItems = false
        let currentEdge = Self.supportedEdges.contains(settings.edge) ? settings.edge : .bottom
        for edge in [DockSettings.Edge.left, .bottom, .right] {
            let item = ActionMenuItem(edge.menuTitle) { [store] in
                store.updateSettings { $0.edge = edge }
            }
            item.state = edge == currentEdge ? .on : .off
            item.isEnabled = Self.supportedEdges.contains(edge)
            positions.addItem(item)
        }
        let position = NSMenuItem(title: "Position on Screen", action: nil, keyEquivalent: "")
        position.submenu = positions
        menu.addItem(position)

        menu.addItem(ActionMenuItem("Remove Divider") { [store] in
            store.remove(id: id)
        })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Dock Settings…") { [weak self] in
            self?.actions.openSettings()
        })
        return menu
    }

    // MARK: - Right-click and control-click

    /// SwiftUI has no secondary-click gesture, and a `.contextMenu` would be a second copy
    /// of this menu, so right-clicks on dividers are caught before they reach the view.
    func installDividerMenuMonitor() {
        guard dividerMenuMonitor == nil else { return }
        dividerMenuMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard event.type == .rightMouseDown || event.modifierFlags.contains(.control) else { return event }
            let windowNumber = event.windowNumber
            let handled = MainActor.assumeIsolated { self?.openDividerMenu(inWindow: windowNumber) ?? false }
            return handled ? nil : event
        }
    }

    func removeDividerMenuMonitor() {
        if let dividerMenuMonitor { NSEvent.removeMonitor(dividerMenuMonitor) }
        dividerMenuMonitor = nil
    }

    private func openDividerMenu(inWindow windowNumber: Int) -> Bool {
        guard let panel, panel.windowNumber == windowNumber,
              let point = layoutPoint(fromScreen: NSEvent.mouseLocation),
              let id = dividerID(at: point)
        else { return false }
        showDividerMenu(for: id)
        return true
    }

    /// The divider item under `point` (layout coordinates), counting the gaps beside it.
    private func dividerID(at point: CGPoint) -> DockItem.ID? {
        let geometry = shellState.geometry
        let margin = geometry.halfGap
        guard let hit = geometry.itemFrames.first(where: { $0.frame.insetBy(dx: -margin, dy: -margin).contains(point) }),
              store.profile.item(id: hit.id)?.isDivider == true
        else { return nil }
        return hit.id
    }
}

/// A menu item that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire(_:)), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("unsupported") }

    @objc private func fire(_ sender: NSMenuItem) { handler() }
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
