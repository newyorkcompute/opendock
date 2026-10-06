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

    /// Frame of the dock window when shown: centered at the bottom of `visibleFrame`.
    ///
    /// The window is larger than the dock surface (it has room around it for magnified
    /// icons, the label, and the shadow) and reaches down to the bottom of the visible
    /// area, so the strip under the dock still counts as "over the dock". It's clamped
    /// to the visible area so its margins never spill onto a neighboring display; the
    /// content is centered and bottom-anchored, so clamping only trims margin.
    public static func shownFrame(contentSize: CGSize, visibleFrame: CGRect) -> CGRect {
        let width = min(contentSize.width, visibleFrame.width)
        let height = min(contentSize.height, visibleFrame.height)
        // Whole points, so the dock stays sharp on 1x displays.
        let x = (visibleFrame.midX - width / 2).rounded(.down)
        return CGRect(x: x, y: visibleFrame.minY, width: width, height: height)
    }

    /// Frame of the dock window when hidden: as when shown, but just below the bottom edge
    /// of the display (the physical edge, not the visible area).
    public static func hiddenFrame(contentSize: CGSize, on screen: Screen) -> CGRect {
        var frame = shownFrame(contentSize: contentSize, visibleFrame: screen.visibleFrame)
        frame.origin.y = screen.frame.minY - frame.height - 1
        return frame
    }

    /// Whether the pointer is touching the bottom edge of the display at `screenFrame`,
    /// which reveals an auto-hidden dock. Only the display's own bottom row counts, not
    /// the rest of a display arranged below it.
    public static func isAtRevealEdge(_ point: CGPoint, of screenFrame: CGRect) -> Bool {
        point.y >= screenFrame.minY - 1
            && point.y <= screenFrame.minY + 1
            && point.x >= screenFrame.minX
            && point.x < screenFrame.maxX
    }
}
