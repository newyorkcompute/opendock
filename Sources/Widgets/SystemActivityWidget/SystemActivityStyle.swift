import DockWidgetKit
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

/// A line chart of 0...1 samples with a soft fill underneath. Samples are spread over
/// the full width, so a history that isn't full yet grows in from the left.
struct Sparkline: View {
    let samples: [Double]
    let capacity: Int
    let color: Color

    var body: some View {
        ZStack {
            if samples.count >= 2 {
                WidgetSparklineSeries(samples: samples, capacity: capacity, color: color, lineWidthFraction: 0.1)
            } else {
                GeometryReader { proxy in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: proxy.size.height - 0.5))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height - 0.5))
                    }
                    .stroke(color.opacity(0.3), lineWidth: 1)
                }
            }
        }
        .animation(.linear(duration: 0.3), value: samples)
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
