import SwiftUI

/// One series of a sparkline: a line through 0...1 samples with a soft gradient fill
/// underneath, newest sample at the right edge. Samples are spread over the full width, so
/// a history that isn't full yet grows in from the left. Draws nothing with fewer than two
/// samples; the caller decides what an empty chart looks like.
///
/// Overlay several in a `ZStack` for a multi-series chart; each lays itself out in the
/// same frame.
public struct WidgetSparklineSeries: View {
    private let samples: [Double]
    private let capacity: Int
    private let color: Color
    private let lineWidthFraction: Double

    /// - Parameters:
    ///   - samples: Values from 0 to 1, oldest first. Anything outside is clamped.
    ///   - capacity: How many samples make a full chart; sets the horizontal scale.
    ///   - color: The line's color; the fill is a faint gradient of it.
    ///   - lineWidthFraction: Stroke width as a fraction of the chart's height, at least 1 pt.
    public init(samples: [Double], capacity: Int, color: Color, lineWidthFraction: Double = 0.08) {
        self.samples = samples
        self.capacity = capacity
        self.color = color
        self.lineWidthFraction = lineWidthFraction
    }

    public var body: some View {
        GeometryReader { proxy in
            let points = SparklineGeometry.points(for: samples, capacity: capacity, in: proxy.size)
            if points.count >= 2 {
                SparklineGeometry.area(under: points, in: proxy.size)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.3), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                SparklineGeometry.line(through: points)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: max(1, proxy.size.height * lineWidthFraction), lineJoin: .round))
            }
        }
    }
}

/// The arithmetic behind `WidgetSparklineSeries`, kept separate so it can be tested.
public enum SparklineGeometry {
    /// Lays out 0...1 `samples` across `size`, one slot per unit of `capacity`, newest at the
    /// right edge. The bottom pixel row is left for the baseline so an idle series stays
    /// visible rather than vanishing into the edge.
    public static func points(for samples: [Double], capacity: Int, in size: CGSize) -> [CGPoint] {
        let slots = max(2, capacity)
        let step = size.width / Double(slots - 1)
        let first = slots - samples.count
        let span = max(0, size.height - 1)
        return samples.enumerated().map { index, sample in
            let clamped = min(1, max(0, sample))
            return CGPoint(x: Double(first + index) * step, y: span - clamped * span)
        }
    }

    /// The polyline through `points`.
    public static func line(through points: [CGPoint]) -> Path {
        Path { path in
            guard let start = points.first else { return }
            path.move(to: start)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }

    /// The region between the polyline through `points` and the bottom edge of `size`.
    public static func area(under points: [CGPoint], in size: CGSize) -> Path {
        Path { path in
            guard let start = points.first, let end = points.last else { return }
            path.move(to: CGPoint(x: start.x, y: size.height))
            for point in points { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: end.x, y: size.height))
            path.closeSubpath()
        }
    }
}
