import SwiftUI
import SystemServices

/// A two-line chart of download and upload rates over the last minute, both on one
/// scale so the busier direction fills the height and the quieter one reads against it.
/// Samples are spread over the full width, so a history that isn't full yet grows in
/// from the left.
struct NetworkSparkline: View {
    let download: [Double]
    let upload: [Double]
    let capacity: Int

    var body: some View {
        let peak = NetworkMath.peak(of: download, upload)
        let downloadSamples = NetworkMath.normalized(download, peak: peak)
        let uploadSamples = NetworkMath.normalized(upload, peak: peak)
        GeometryReader { proxy in
            ZStack {
                if downloadSamples.count < 2 && uploadSamples.count < 2 {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: proxy.size.height - 0.5))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height - 0.5))
                    }
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                } else {
                    series(downloadSamples, color: NetworkStyle.color(for: .download), in: proxy.size)
                    series(uploadSamples, color: NetworkStyle.color(for: .upload), in: proxy.size)
                }
            }
        }
        .animation(.linear(duration: 0.3), value: download)
        .animation(.linear(duration: 0.3), value: upload)
    }

    @ViewBuilder
    private func series(_ samples: [Double], color: Color, in size: CGSize) -> some View {
        let points = Self.points(for: samples, capacity: capacity, in: size)
        if points.count >= 2 {
            Path { path in
                path.move(to: CGPoint(x: points[0].x, y: size.height))
                for point in points { path.addLine(to: point) }
                path.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(colors: [color.opacity(0.3), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            Path { path in
                path.move(to: points[0])
                for point in points.dropFirst() { path.addLine(to: point) }
            }
            .stroke(color, style: StrokeStyle(lineWidth: max(1, size.height * 0.08), lineJoin: .round))
        }
    }

    /// Lays out 0...1 `samples` across `size`, one slot per `capacity`, newest at the right
    /// edge. The bottom pixel row is left for the baseline so an idle series stays visible.
    static func points(for samples: [Double], capacity: Int, in size: CGSize) -> [CGPoint] {
        let slots = max(2, capacity)
        let step = size.width / Double(slots - 1)
        let first = slots - samples.count
        return samples.enumerated().map { index, sample in
            let clamped = min(1, max(0, sample))
            return CGPoint(
                x: Double(first + index) * step,
                y: (size.height - 1) - clamped * (size.height - 1))
        }
    }
}
