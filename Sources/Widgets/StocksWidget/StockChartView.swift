import SwiftUI
import SystemServices

/// A line of closing prices with a soft fill under it and, when there is one, a dashed
/// line at the previous close. Green above the baseline's day, red below, like the Stocks
/// app. The tile draws it small; the popover draws it big.
struct StockChartView: View {
    let chart: StockChart?
    /// The trading session a one-day chart is spread over; nil spaces the points evenly.
    var session: DateInterval?
    var showsBaseline = true

    var body: some View {
        let layout = chart.map { StockChartLayout.make(chart: $0, session: session) }
        let color = StockStyle.color(for: StockMove(change: chart?.change))
        GeometryReader { proxy in
            let size = proxy.size
            let points = Self.points(for: layout, in: size)
            ZStack {
                if points.count < 2 {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: size.height / 2))
                        path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    }
                    .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                } else {
                    if showsBaseline, let baseline = layout?.baseline {
                        let y = Self.y(for: baseline, in: size)
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        }
                        .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    }
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: size.height))
                        for point in points { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.3), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: max(1, min(2, size.height * 0.06)), lineJoin: .round))
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: chart?.closes)
        .accessibilityHidden(true)
    }

    /// Lays the layout out in `size`, leaving a pixel at the top and bottom for the stroke.
    static func points(for layout: StockChartLayout?, in size: CGSize) -> [CGPoint] {
        guard let layout, layout.values.count >= 2 else { return [] }
        return zip(layout.positions, layout.values).map { position, value in
            CGPoint(x: position * size.width, y: y(for: value, in: size))
        }
    }

    private static func y(for value: Double, in size: CGSize) -> CGFloat {
        let clamped = min(1, max(0, value))
        return (size.height - 1) - clamped * (size.height - 2)
    }
}
