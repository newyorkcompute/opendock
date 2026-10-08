import DockCore
import SwiftUI

extension View {
    /// Bounces the view while its app launches (see `LaunchBounce`).
    func launchBounce(_ bounce: LaunchBounce?) -> some View {
        modifier(LaunchBounceEffect(bounce: bounce))
    }
}

/// Draws an icon hopping while its app launches. The hop is applied after layout, so the
/// row, magnification, and hover targets don't move with it, and it scales with the icon
/// as drawn, so a magnified icon hops higher. The hop goes away from the screen edge: up
/// from a bottom dock, sideways into the screen from a side dock. The window has room
/// past the row for the highest hop (see `DockRowMetrics.launchBounceHeight`). With
/// Reduce Motion, the icon stays put and fades in time with the hops instead.
struct LaunchBounceEffect: ViewModifier {
    let bounce: LaunchBounce?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dockEdge) private var edge

    func body(content: Content) -> some View {
        // Paused, so nothing is redrawn, while the icon is at rest.
        TimelineView(.animation(paused: bounce == nil)) { timeline in
            let lift = reduceMotion ? 0 : bounce?.lift(at: timeline.date) ?? 0
            let edge = edge
            content
                .opacity(reduceMotion ? bounce?.reducedMotionOpacity(at: timeline.date) ?? 1 : 1)
                .visualEffect { content, geometry in
                    let offset = lift * LaunchBounce.peakOffset(iconHeight: edge.axis.thickness(of: geometry.size))
                    return switch edge {
                    case .bottom: content.offset(x: 0, y: -offset)
                    case .left: content.offset(x: offset, y: 0)
                    case .right: content.offset(x: -offset, y: 0)
                    }
                }
        }
    }
}
