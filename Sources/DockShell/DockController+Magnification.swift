import AppKit
import SwiftUI

/// Pointer tracking for magnification and item labels.
///
/// SwiftUI hover reports pointer moves over the dock. Magnification is on while the
/// pointer is inside the layout's hit zone (the surface, the magnified icons above it,
/// and the strip down to the screen edge). Nothing runs while the pointer is elsewhere:
/// the only global monitor is installed on entry and removed on exit.
extension DockController {
    func pointerHoverChanged(_ phase: HoverPhase) {
        switch phase {
        case let .active(location): pointerMoved(to: location)
        case .ended: pointerMoved(to: nil)
        }
    }

    /// `location` is in the dock layout's coordinates; nil when it left the window.
    func pointerMoved(to location: CGPoint?) {
        guard shellState.isVisible, !shellState.isInteracting else { return }
        let geometry = shellState.geometry
        guard let location, geometry.hitZone.contains(location) else {
            pointerLeftDock()
            return
        }

        if store.settings.peakMagnification > 1, shellState.pointerX != location.x {
            shellState.pointerX = location.x
        }
        // No labels during a drag: the items are on the move.
        let hovered = shellState.isDragging ? nil : geometry.item(atX: location.x)
        if shellState.hoveredItemID != hovered {
            shellState.hoveredItemID = hovered
        }

        guard !shellState.isPointerInside else { return }
        shellState.isPointerInside = true
        withAnimation(.dockMagnify) { shellState.magnification = 1 }
        holdUntilPointerEnters = false
        cancelScheduledHide()
        installHoverMonitor()
    }

    func pointerLeftDock() {
        removeHoverMonitor()
        guard shellState.isPointerInside else { return }
        shellState.isPointerInside = false
        shellState.hoveredItemID = nil
        withAnimation(.dockDemagnify) { shellState.magnification = 0 }
        scheduleHide()
    }

    /// Drop all hover state at once, e.g. when the dock slides away.
    func resetMagnification() {
        removeHoverMonitor()
        shellState.isPointerInside = false
        shellState.hoveredItemID = nil
        shellState.pointerX = nil
        shellState.magnification = 0
    }

    // MARK: - Leaving through transparent areas

    /// The window is bigger than the dock and its empty parts let events through to
    /// whatever is underneath, so the dock may never hear that the pointer left. While
    /// the pointer is inside, a global monitor (which only sees events sent to other
    /// apps) covers that case.
    private func installHoverMonitor() {
        guard hoverMonitor == nil else { return }
        let handler: @Sendable (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pointerMoved(to: self.layoutPoint(fromScreen: NSEvent.mouseLocation))
            }
        }
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler)
    }

    func removeHoverMonitor() {
        if let hoverMonitor { NSEvent.removeMonitor(hoverMonitor) }
        hoverMonitor = nil
    }

    // MARK: - Coordinate conversion

    /// Screen point to the dock layout's coordinates.
    func layoutPoint(fromScreen point: NSPoint) -> CGPoint? {
        guard let panel, let hostingView else { return nil }
        var local = hostingView.convert(panel.convertPoint(fromScreen: point), from: nil)
        if !hostingView.isFlipped { local.y = hostingView.bounds.height - local.y }
        let origin = shellState.geometry.containerOrigin
        return CGPoint(x: local.x - origin.x, y: local.y - origin.y)
    }

    /// The layout's hit zone in screen coordinates, once it has been laid out.
    var hitZoneOnScreen: NSRect? {
        guard let panel, let hostingView else { return nil }
        let zone = shellState.geometry.hitZone
        guard !zone.isEmpty else { return nil }
        let origin = shellState.geometry.containerOrigin
        var rect = zone.offsetBy(dx: origin.x, dy: origin.y)
        if !hostingView.isFlipped { rect.origin.y = hostingView.bounds.height - rect.maxY }
        return panel.convertToScreen(hostingView.convert(rect, to: nil))
    }
}
