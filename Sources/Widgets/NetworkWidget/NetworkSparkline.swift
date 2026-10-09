import DockWidgetKit
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
        ZStack {
            if downloadSamples.count < 2 && uploadSamples.count < 2 {
                GeometryReader { proxy in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: proxy.size.height - 0.5))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height - 0.5))
                    }
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                }
            } else {
                WidgetSparklineSeries(
                    samples: downloadSamples, capacity: capacity, color: NetworkStyle.color(for: .download))
                WidgetSparklineSeries(
                    samples: uploadSamples, capacity: capacity, color: NetworkStyle.color(for: .upload))
            }
        }
        .animation(.linear(duration: 0.3), value: download)
        .animation(.linear(duration: 0.3), value: upload)
    }
}
