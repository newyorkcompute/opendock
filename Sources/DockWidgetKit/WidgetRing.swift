import SwiftUI

/// A circular gauge: a faint track plus a rounded colored arc from 12 o'clock covering
/// `fraction` of the circle. Fills the frame it's given, so size it with `.frame` and
/// put a symbol or number in an `.overlay`.
///
/// Values outside 0...1 are clamped, and an empty ring still shows a dot so the arc's
/// start is visible.
public struct WidgetRing: View {
    private let fraction: Double
    private let color: Color
    private let lineWidth: Double
    private let animation: Animation?

    /// - Parameters:
    ///   - fraction: How much of the circle to fill, 0...1.
    ///   - color: The arc's color; the track is a faint version of it.
    ///   - lineWidth: The stroke width. The ring insets itself by half of it so the stroke
    ///     stays inside the frame.
    ///   - animation: How the arc moves when `fraction` changes. A ring that ticks once a
    ///     second should pass `.linear(duration: 1)` so it sweeps continuously; `nil` jumps.
    public init(
        fraction: Double, color: Color, lineWidth: Double, animation: Animation? = .easeOut(duration: 0.3)
    ) {
        self.fraction = fraction
        self.color = color
        self.lineWidth = lineWidth
        self.animation = animation
    }

    public var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .animation(animation, value: fraction)
    }
}
