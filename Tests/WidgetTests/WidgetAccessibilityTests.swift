import DockWidgetKit
import Testing

@Suite("Widget accessibility copy")
struct WidgetAccessibilityTests {
    @Test func phraseDropsBlanksAndTrims() {
        #expect(WidgetAccessibility.phrase([" Battery ", "", "  ", "low"]) == "Battery, low")
        #expect(WidgetAccessibility.phrase([]) == "")
        #expect(WidgetAccessibility.phrase(["", "  "]) == "")
    }

    @Test func readingKeepsTheNameSeparateFromTheState() {
        let reading = WidgetAccessibility.reading("Battery", value: ["18 percent", "low", "On battery"])
        #expect(reading.label == "Battery")
        #expect(reading.value == "18 percent, low, On battery")
        #expect(WidgetAccessibility.reading("Clock", value: []).value == "")
    }

    @Test func percentSpeaksANumberOrUnknown() {
        #expect(WidgetAccessibility.percent(0) == "0 percent")
        #expect(WidgetAccessibility.percent(72) == "72 percent")
        #expect(WidgetAccessibility.percent(nil) == "unknown")
        #expect(WidgetAccessibility.percent(fraction: 0.855) == "86 percent")
        #expect(WidgetAccessibility.percent(fraction: 0) == "0 percent")
        #expect(WidgetAccessibility.percent(fraction: 1) == "100 percent")
        #expect(WidgetAccessibility.percent(fraction: nil) == "unknown")
    }

    @Test func chargeLevelMatchesTheBatteryColorBands() {
        #expect(WidgetAccessibility.chargeLevel(percent: nil) == nil)
        #expect(WidgetAccessibility.chargeLevel(percent: 0) == "low")
        #expect(WidgetAccessibility.chargeLevel(percent: 19) == "low")
        #expect(WidgetAccessibility.chargeLevel(percent: 20) == "medium")
        #expect(WidgetAccessibility.chargeLevel(percent: 49) == "medium")
        #expect(WidgetAccessibility.chargeLevel(percent: 50) == "good")
        #expect(WidgetAccessibility.chargeLevel(percent: 100) == "good")
    }
}
