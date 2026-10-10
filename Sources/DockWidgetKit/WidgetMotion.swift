import SwiftUI

extension View {
    /// Animates changes to `value`, or jumps when Reduce Motion is on.
    public func animationRespectingReduceMotion<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(ReduceMotionAnimationModifier(animation: animation, value: value))
    }
}

private struct ReduceMotionAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var animation: Animation?
    var value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
