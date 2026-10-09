import AppKit
import DockCore
import SwiftUI

/// What the drag-off overlay shows, set by the controller and read by its view.
@Observable
final class DragOffOverlayState {
    /// Where the dragged icon's center is, in the overlay view's coordinates (y down).
    var iconCenter: CGPoint?
    /// True while letting go removes the item: the icon is labeled "Remove".
    var isArmed = false
    /// The poof playing now, if any.
    var poof: Poof?
    /// The dock's icon size, which the label's distance from the icon and the poof's size
    /// follow.
    var iconSize: CGFloat = 64

    nonisolated struct Poof: Equatable {
        /// Where the icon was let go, in the overlay view's coordinates.
        var center: CGPoint
        /// Side of the square the cloud is drawn in.
        var size: CGFloat
        var startedAt: Date
    }
}

/// Covers the dock's screen while one of the row's items is dragged off the dock (see
/// `DockController+DragOff.swift`).
///
/// It's a drag destination for the whole screen, so the dock hears where the drag is, and
/// when it's let go, once it has left the dock's window, and so that a drop that removes
/// the item is accepted rather than refused: a refused drop slides the icon back onto the
/// dock, right through the poof. It also draws the "Remove" label by the icon, and the poof.
///
/// Ordered just below the dock's panel, so the dock still takes drags over itself, and
/// taken down as soon as the drag ends (after the poof, if there is one).
final class DragOffOverlayPanel: NSPanel {
    let state = DragOffOverlayState()
    private let destination = DragOffDestinationView()

    init(screen: NSScreen, collectionBehavior: NSWindow.CollectionBehavior, controller: DockController) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        self.collectionBehavior = collectionBehavior
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isMovable = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        tabbingMode = .disallowed

        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        let hosting = NSHostingView(rootView: DragOffOverlayView(state: state))
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        destination.controller = controller
        destination.frame = container.bounds
        destination.autoresizingMask = [.width, .height]
        destination.registerForDraggedTypes([.string])
        container.addSubview(hosting)
        // On top, so the drag lands on it rather than on the hosting view.
        container.addSubview(destination)
        contentView = container
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// `point` on the screen in the overlay view's coordinates (origin top left, y down).
    func viewPoint(fromScreen point: NSPoint) -> CGPoint {
        let local = convertPoint(fromScreen: point)
        return CGPoint(x: local.x, y: frame.height - local.y)
    }

    /// Once the drag is over the overlay only stays up for the poof, and mustn't catch the
    /// clicks meant for what's under it.
    func stopReceivingEvents() {
        ignoresMouseEvents = true
    }
}

/// The drop destination filling the overlay; the controller decides what to make of the
/// drag. Drawn nearly, not fully, transparent: the window server lets events through
/// fully transparent pixels (see `DockHitZone`).
private final class DragOffDestinationView: NSView {
    weak var controller: DockController?

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.005).setFill()
        dirtyRect.fill()
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        controller?.dragOffUpdated(sender) ?? []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        controller?.dragOffUpdated(sender) ?? []
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        controller?.performDragOffDrop(sender) ?? false
    }
}

/// The "Remove" label by the dragged icon, and the poof where it was let go.
struct DragOffOverlayView: View {
    let state: DragOffOverlayState

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if state.isArmed, let center = state.iconCenter {
                // Just above the icon, like the Dock's labels sit above its icons.
                DockItemLabel(title: "Remove", truncates: false)
                    .position(
                        x: center.x,
                        y: center.y - state.iconSize / 2 - DockRowMetrics.labelGap - DockRowMetrics.labelHeight / 2
                    )
                    .transition(.opacity)
            }
            if let poof = state.poof {
                PoofView(poof: poof)
                    .position(poof.center)
                    .id(poof.startedAt)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Draws `PoofCloud`, frame by frame, from when the poof started. The cloud is our own
/// drawing: soft gray puffs that billow out and fade. With Reduce Motion on it only fades.
struct PoofView: View {
    let poof: DragOffOverlayState.Poof

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { timeline in
            let progress = timeline.date.timeIntervalSince(poof.startedAt) / PoofCloud.duration
            Canvas { context, size in
                let scale = size.width / 2
                let origin = CGPoint(x: size.width / 2, y: size.height / 2)
                context.addFilter(.shadow(color: .black.opacity(0.25), radius: scale * 0.05, y: scale * 0.02))
                context.addFilter(.blur(radius: scale * 0.05))
                for puff in PoofCloud.puffs(at: progress, reduceMotion: reduceMotion) {
                    let radius = puff.radius * scale
                    let rect = CGRect(
                        x: origin.x + puff.x * scale - radius,
                        y: origin.y + puff.y * scale - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(Circle().path(in: rect), with: .color(Color(white: 0.86).opacity(puff.opacity)))
                }
            }
        }
        .frame(width: poof.size, height: poof.size)
        .accessibilityHidden(true)
    }
}
