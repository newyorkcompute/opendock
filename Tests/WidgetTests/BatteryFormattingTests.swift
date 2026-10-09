import Foundation
import SwiftUI
import Testing

@testable import BatteryWidget

@MainActor
@Suite("Battery formatting")
struct BatteryFormattingTests {
    @Test func colorTracksChargeLevelUnlessCharging() {
        #expect(BatteryFormatting.color(percentage: nil, isCharging: false) == .secondary)
        #expect(BatteryFormatting.color(percentage: 100, isCharging: false) == .green)
        #expect(BatteryFormatting.color(percentage: 50, isCharging: false) == .green)
        #expect(BatteryFormatting.color(percentage: 49, isCharging: false) == .yellow)
        #expect(BatteryFormatting.color(percentage: 20, isCharging: false) == .yellow)
        #expect(BatteryFormatting.color(percentage: 19, isCharging: false) == .red)
        #expect(BatteryFormatting.color(percentage: 5, isCharging: true) == .green)
    }

    @Test func durationIsHoursAndZeroPaddedMinutes() {
        #expect(BatteryFormatting.duration(minutes: 0) == "0:00")
        #expect(BatteryFormatting.duration(minutes: 7) == "0:07")
        #expect(BatteryFormatting.duration(minutes: 134) == "2:14")
        #expect(BatteryFormatting.duration(minutes: 600) == "10:00")
    }

    @Test func captionCoversEveryPowerState() {
        func caption(
            hasBattery: Bool = true, charged: Bool = false, charging: Bool = false, pluggedIn: Bool = false,
            minutes: Int? = nil
        ) -> String {
            BatteryFormatting.caption(
                hasBattery: hasBattery, isFullyCharged: charged, isCharging: charging, isPluggedIn: pluggedIn,
                timeRemainingMinutes: minutes)
        }
        #expect(caption(hasBattery: false, pluggedIn: true) == "Power adapter")
        #expect(caption(charged: true, charging: true, pluggedIn: true, minutes: 0) == "Charged")
        #expect(caption(charging: true, pluggedIn: true, minutes: 75) == "1:15 to full")
        #expect(caption(charging: true, pluggedIn: true) == "Charging")
        #expect(caption(pluggedIn: true, minutes: 75) == "Plugged in")
        #expect(caption(minutes: 190) == "3:10 left")
        #expect(caption() == "On battery")
    }

    @Test func accessorySymbolIsGuessedFromTheName() {
        #expect(BatteryFormatting.symbol(forAccessory: "Dan's AirPods Pro") == "airpods")
        #expect(BatteryFormatting.symbol(forAccessory: "Magic Mouse") == "magicmouse")
        #expect(BatteryFormatting.symbol(forAccessory: "Magic Keyboard") == "keyboard")
        #expect(BatteryFormatting.symbol(forAccessory: "Magic Trackpad") == "rectangle.and.hand.point.up.left")
        #expect(BatteryFormatting.symbol(forAccessory: "Game Controller") == "dot.radiowaves.left.and.right")
    }

    @Test func batteryGlyphRoundsToTheNearestQuarter() {
        #expect(BatteryFormatting.batterySymbol(percentage: nil) == "battery.0percent")
        #expect(BatteryFormatting.batterySymbol(percentage: 12) == "battery.0percent")
        #expect(BatteryFormatting.batterySymbol(percentage: 13) == "battery.25percent")
        #expect(BatteryFormatting.batterySymbol(percentage: 37) == "battery.25percent")
        #expect(BatteryFormatting.batterySymbol(percentage: 38) == "battery.50percent")
        #expect(BatteryFormatting.batterySymbol(percentage: 62) == "battery.50percent")
        #expect(BatteryFormatting.batterySymbol(percentage: 63) == "battery.75percent")
        #expect(BatteryFormatting.batterySymbol(percentage: 87) == "battery.75percent")
        #expect(BatteryFormatting.batterySymbol(percentage: 88) == "battery.100percent")
        #expect(BatteryFormatting.batterySymbol(percentage: 100) == "battery.100percent")
    }
}
