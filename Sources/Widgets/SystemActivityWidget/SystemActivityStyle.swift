import SwiftUI
import SystemServices

/// Colors and small shapes shared by the tile and the popover.
enum SystemActivityStyle {
    static func color(for level: ActivityLevel) -> Color {
        switch level {
        case .low: .green
        case .elevated: .yellow
        case .high: .red
        }
    }

    static func cpuColor(_ usage: CPUUsage?) -> Color {
        guard let usage else { return .secondary }
        return color(for: SystemActivityMath.cpuLevel(usage.total))
    }

    static func memoryColor(_ memory: MemorySnapshot?, pressure: MemoryPressure) -> Color {
        guard let memory else { return .secondary }
        return color(for: SystemActivityMath.memoryLevel(usedFraction: memory.usedFraction, pressure: pressure))
    }

    static func diskColor(_ disk: DiskSnapshot?) -> Color {
        guard let disk else { return .secondary }
        return color(for: SystemActivityMath.diskLevel(disk.usedFraction))
    }
}

/// A circular gauge: faint track plus a colored arc from 12 o'clock.
struct ActivityRing: View {
    let progress: Double
    let color: Color
    let lineWidth: Double

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .animation(.easeOut(duration: 0.4), value: progress)
    }
}

/// A line chart of 0...1 samples with a soft fill underneath. Samples are spread over
/// the full width, so a history that isn't full yet grows in from the left.
struct Sparkline: View {
    let samples: [Double]
    let capacity: Int
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let points = Self.points(for: samples, capacity: capacity, in: proxy.size)
            if points.count >= 2 {
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        for point in points { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: max(1, proxy.size.height * 0.1), lineJoin: .round))
                }
            } else {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: proxy.size.height - 0.5))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height - 0.5))
                }
                .stroke(color.opacity(0.3), lineWidth: 1)
            }
        }
        .animation(.linear(duration: 0.3), value: samples)
    }

    /// Lays out `samples` across `size`, one slot per `capacity`, newest at the right edge.
    static func points(for samples: [Double], capacity: Int, in size: CGSize) -> [CGPoint] {
        let slots = max(2, capacity)
        let step = size.width / Double(slots - 1)
        let first = slots - samples.count
        return samples.enumerated().map { index, sample in
            let clamped = min(1, max(0, sample))
            return CGPoint(
                x: Double(first + index) * step,
                y: size.height - clamped * size.height)
        }
    }
}

/// A horizontal capacity bar made of colored segments over a faint track.
struct SegmentedBar: View {
    struct Segment: Identifiable {
        let id: Int
        let fraction: Double
        let color: Color
    }

    let segments: [Segment]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.08))
                HStack(spacing: 0) {
                    ForEach(segments) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: max(0, min(1, segment.fraction)) * width)
                    }
                }
                .clipShape(Capsule())
            }
        }
        .animation(.easeOut(duration: 0.4), value: segments.map(\.fraction))
    }
}
