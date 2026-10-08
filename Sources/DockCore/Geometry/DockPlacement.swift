import CoreGraphics
import Foundation

/// Where the dock window goes: which display, and its frame there. Pure math over plain
/// display descriptions so it can be unit tested; the shell feeds it `NSScreen` values.
///
/// All rectangles are in AppKit's global screen coordinates: the origin is the bottom-left
/// corner of the main display and y grows upward, so displays left of or below the main
/// display have negative coordinates.
public enum DockPlacement {
    public struct Screen: Hashable, Sendable {
        /// CoreGraphics display UUID; nil if the system couldn't provide one.
        public var id: String?
        public var name: String
        public var frame: CGRect
        /// `frame` minus the menu bar and Apple's Dock, if it's on this display.
        public var visibleFrame: CGRect

        public init(id: String?, name: String, frame: CGRect, visibleFrame: CGRect) {
            self.id = id
            self.name = name
            self.frame = frame
            self.visibleFrame = visibleFrame
        }
    }

    /// Index into `screens` of the display the dock belongs on, or nil when there are none.
    ///
    /// - Parameters:
    ///   - screens: Connected displays in `NSScreen.screens` order: the first one is the
    ///     main display.
    ///   - activeIndex: The display with the active menu bar, if known.
    ///
    /// Every preference falls back to the main display: `.active` while the active display
    /// is unknown, `.specific` while that display is disconnected.
    public static func screenIndex(
        for preference: DockSettings.Display,
        in screens: [Screen],
        activeIndex: Int?
    ) -> Int? {
        guard !screens.isEmpty else { return nil }
        switch preference {
        case .main:
            return 0
        case .active:
            guard let activeIndex, screens.indices.contains(activeIndex) else { return 0 }
            return activeIndex
        case let .specific(id, _):
            return screens.firstIndex { $0.id == id } ?? 0
        }
    }

    /// Frame of the dock window when shown: centered along `edge` of `visibleFrame`, touching it.
    ///
    /// The window is larger than the dock surface (it has room around it for magnified
    /// icons, the label, and the shadow) and reaches to the edge of the visible area, so
    /// the strip between the dock and the screen edge still counts as "over the dock".
    /// It's clamped to the visible area so its margins never spill onto a neighboring
    /// display; the content is centered and anchored to the edge, so clamping only trims
    /// margin.
    public static func shownFrame(
        contentSize: CGSize,
        visibleFrame: CGRect,
        edge: DockSettings.Edge = .bottom
    ) -> CGRect {
        let width = min(contentSize.width, visibleFrame.width)
        let height = min(contentSize.height, visibleFrame.height)
        // Whole points, so the dock stays sharp on 1x displays.
        switch edge {
        case .bottom:
            let x = (visibleFrame.midX - width / 2).rounded(.down)
            return CGRect(x: x, y: visibleFrame.minY, width: width, height: height)
        case .left:
            let y = (visibleFrame.midY - height / 2).rounded(.down)
            return CGRect(x: visibleFrame.minX, y: y, width: width, height: height)
        case .right:
            let y = (visibleFrame.midY - height / 2).rounded(.down)
            return CGRect(x: visibleFrame.maxX - width, y: y, width: width, height: height)
        }
    }

    /// Frame of the dock window when hidden: as when shown, but just past `edge` of the
    /// display (the physical edge, not the visible area).
    public static func hiddenFrame(contentSize: CGSize, on screen: Screen, edge: DockSettings.Edge = .bottom) -> CGRect
    {
        var frame = shownFrame(contentSize: contentSize, visibleFrame: screen.visibleFrame, edge: edge)
        switch edge {
        case .bottom: frame.origin.y = screen.frame.minY - frame.height - 1
        case .left: frame.origin.x = screen.frame.minX - frame.width - 1
        case .right: frame.origin.x = screen.frame.maxX + 1
        }
        return frame
    }

    /// Whether the pointer is touching `edge` of the display at `screenFrame`, which
    /// reveals an auto-hidden dock. Only the display's own edge row counts, not the rest
    /// of a display arranged past it.
    ///
    /// The pointer stops on the edge pixel: at `minY + 1` along the bottom in AppKit
    /// coordinates, at `minX` on the left, and at `maxX - 1` on the right. A point of slack
    /// on either side covers fractional positions.
    public static func isAtRevealEdge(_ point: CGPoint, of screenFrame: CGRect, edge: DockSettings.Edge = .bottom)
        -> Bool
    {
        switch edge {
        case .bottom:
            return point.y >= screenFrame.minY - 1
                && point.y <= screenFrame.minY + 1
                && point.x >= screenFrame.minX
                && point.x < screenFrame.maxX
        case .left:
            return point.x >= screenFrame.minX - 1
                && point.x <= screenFrame.minX + 1
                && point.y >= screenFrame.minY
                && point.y < screenFrame.maxY
        case .right:
            return point.x >= screenFrame.maxX - 2
                && point.x <= screenFrame.maxX + 1
                && point.y >= screenFrame.minY
                && point.y < screenFrame.maxY
        }
    }

    /// `rect` stretched to `edge` of the display at `screenFrame`, so that the strip
    /// between the dock and the screen edge counts as part of it. Without the strip, a
    /// pointer resting on the edge (where it revealed the dock) would count as outside the
    /// dock and hide it again.
    public static func reachingScreenEdge(_ rect: CGRect, of screenFrame: CGRect, edge: DockSettings.Edge) -> CGRect {
        var rect = rect
        switch edge {
        case .bottom:
            let gap = rect.minY - screenFrame.minY
            if gap > 0 {
                rect.origin.y -= gap
                rect.size.height += gap
            }
        case .left:
            let gap = rect.minX - screenFrame.minX
            if gap > 0 {
                rect.origin.x -= gap
                rect.size.width += gap
            }
        case .right:
            let gap = screenFrame.maxX - rect.maxX
            if gap > 0 {
                rect.size.width += gap
            }
        }
        return rect
    }
}
