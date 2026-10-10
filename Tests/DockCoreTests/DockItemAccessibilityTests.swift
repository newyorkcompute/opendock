import DockCore
import Testing

@Suite("Dock item accessibility values")
struct DockItemAccessibilityTests {
    @Test func aRunningAppSaysRunning() {
        #expect(DockItemAccessibility.appValue(exists: true, isRunning: true, badge: nil) == "Running")
    }

    @Test func aBadgeIsIncludedWithTheState() {
        #expect(DockItemAccessibility.appValue(exists: true, isRunning: true, badge: "3") == "Running, 3")
        #expect(DockItemAccessibility.appValue(exists: true, isRunning: false, badge: " 12 ") == "12")
    }

    @Test func aMissingAppSaysMissingAndDropsRunning() {
        #expect(DockItemAccessibility.appValue(exists: false, isRunning: true, badge: nil) == "Missing")
        #expect(DockItemAccessibility.appValue(exists: false, isRunning: false, badge: "1") == "Missing, 1")
    }

    @Test func anIdleAppWithNoBadgeHasNoValue() {
        #expect(DockItemAccessibility.appValue(exists: true, isRunning: false, badge: nil) == "")
        #expect(DockItemAccessibility.appValue(exists: true, isRunning: false, badge: "  ") == "")
    }
}
