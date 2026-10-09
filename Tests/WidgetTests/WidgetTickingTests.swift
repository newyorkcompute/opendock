import DockWidgetKit
import Foundation
import Testing

@MainActor
@Suite("Widget tick schedule")
struct WidgetTickingTests {
    @Test func ticksAtTheIntervalOnlyWhileActiveAndVisible() {
        #expect(WidgetTickSchedule.period(interval: 1, active: true, visible: true) == 1)
        #expect(WidgetTickSchedule.period(interval: 1, active: false, visible: true) == WidgetTickSchedule.idleInterval)
        #expect(WidgetTickSchedule.period(interval: 1, active: true, visible: false) == WidgetTickSchedule.idleInterval)
        #expect(
            WidgetTickSchedule.period(interval: 1, active: false, visible: false) == WidgetTickSchedule.idleInterval)
    }

    @Test func startIsAlignedToWholePeriods() {
        let now = Date(timeIntervalSinceReferenceDate: 1234.56)
        #expect(WidgetTickSchedule.start(for: 1, now: now).timeIntervalSinceReferenceDate == 1234)
        #expect(WidgetTickSchedule.start(for: 60, now: now).timeIntervalSinceReferenceDate == 1200)
        #expect(
            WidgetTickSchedule.start(for: 0.1, now: now).timeIntervalSinceReferenceDate.isApproximatelyEqual(to: 1234.5)
        )
    }

    @Test func startIsNeverAfterNowAndStableWithinOnePeriod() {
        let base = Date(timeIntervalSinceReferenceDate: 7_200)
        let start = WidgetTickSchedule.start(for: 60, now: base)
        #expect(start == base)
        #expect(WidgetTickSchedule.start(for: 60, now: base.addingTimeInterval(59.9)) == start)
        #expect(WidgetTickSchedule.start(for: 60, now: base.addingTimeInterval(60)) == start.addingTimeInterval(60))
    }
}

extension Double {
    fileprivate func isApproximatelyEqual(to other: Double, tolerance: Double = 1e-9) -> Bool {
        abs(self - other) <= tolerance
    }
}
