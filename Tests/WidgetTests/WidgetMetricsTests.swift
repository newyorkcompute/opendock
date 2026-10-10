import DockWidgetKit
import Testing

@MainActor
@Suite("Widget text size")
struct WidgetMetricsTests {
    @Test func secondaryTextStaysAtLeastElevenPoints() {
        #expect(WidgetMetrics.secondaryFontSize(for: 32) == 11)
        #expect(WidgetMetrics.secondaryFontSize(for: 48) == 11)
        #expect(WidgetMetrics.secondaryFontSize(for: 55) == 11)
        // 96 * 0.2 is not exactly 19.2 in Double.
        #expect(WidgetMetrics.secondaryFontSize(for: 96) == 96 * 0.2)
        #expect(WidgetMetrics.primaryFontSize(for: 32) == 12)
    }

    @Test func textDoesNotScaleBelowElevenPoints() {
        #expect(WidgetMetrics.minimumReadableScale(for: 9) == 1)
        #expect(WidgetMetrics.minimumReadableScale(for: 11) == 1)
        #expect(WidgetMetrics.minimumReadableScale(for: 12) == 11.0 / 12)
        #expect(WidgetMetrics.minimumReadableScale(for: 22) == 0.5)
    }
}
