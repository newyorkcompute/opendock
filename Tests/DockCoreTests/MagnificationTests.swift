import Foundation
import Testing
@testable import DockCore

@Suite("Dock magnification geometry")
struct MagnificationTests {
    private let pitch = 54.0
    private let peak = 1.5
    private var radius: Double { 3 * pitch }

    private func icons(_ count: Int) -> [DockMagnification.Slot] {
        Array(repeating: .init(width: pitch, magnifies: true), count: count)
    }

    private func center(of index: Int) -> Double { (Double(index) + 0.5) * pitch }

    @Test func falloffIsSmoothBell() {
        #expect(DockMagnification.falloff(distance: 0, radius: 100) == 1)
        #expect(abs(DockMagnification.falloff(distance: 50, radius: 100) - 0.5) < 1e-12)
        #expect(DockMagnification.falloff(distance: -50, radius: 100) == DockMagnification.falloff(distance: 50, radius: 100))
        #expect(DockMagnification.falloff(distance: 100, radius: 100) == 0)
        #expect(DockMagnification.falloff(distance: 250, radius: 100) == 0)
        // Zero slope at the edge: no visible "pop" as an item enters the range.
        #expect(DockMagnification.falloff(distance: 99, radius: 100) < 0.001)
    }

    @Test func noPointerMeansRestingLayout() {
        let row = DockMagnification.row(icons(5), pointer: nil, peakScale: peak, radius: radius)
        #expect(row.scales == [1, 1, 1, 1, 1])
        #expect(row.origins == [0, 54, 108, 162, 216])
    }

    @Test func zeroAmountMeansRestingLayout() {
        let row = DockMagnification.row(icons(5), pointer: center(of: 2), peakScale: peak, radius: radius, amount: 0)
        #expect(row.origins == [0, 54, 108, 162, 216])
    }

    @Test func itemUnderPointerPeaksAndNeighborsFallOff() {
        let row = DockMagnification.row(icons(9), pointer: center(of: 4), peakScale: peak, radius: radius)
        #expect(abs(row.scales[4] - peak) < 1e-12)
        #expect(row.scales[3] == row.scales[5])
        #expect(row.scales[3] > row.scales[2])
        #expect(row.scales[2] > row.scales[1])
        #expect(row.scales[1] == 1) // 3 pitches away: out of range
        #expect(row.scales[3] < peak && row.scales[3] > 1)
    }

    @Test func pointStaysUnderPointer() {
        let slots = icons(7)
        for pointer in stride(from: 0.0, through: 7 * pitch - 0.1, by: 7.3) {
            let row = DockMagnification.row(slots, pointer: pointer, peakScale: peak, radius: radius)
            guard let k = row.slotIndex(at: pointer) else {
                Issue.record("pointer \(pointer) not inside any slot")
                continue
            }
            // The pointer sits at the same fraction of the magnified slot as of the resting one.
            let restingFraction = (pointer - Double(k) * pitch) / pitch
            let magnifiedFraction = (pointer - row.origins[k]) / row.widths[k]
            #expect(abs(restingFraction - magnifiedFraction) < 1e-9)
        }
    }

    @Test func neighborsPushOutwardSymmetrically() {
        let row = DockMagnification.row(icons(9), pointer: center(of: 4), peakScale: peak, radius: radius)
        let restingWidth = 9 * pitch
        #expect(row.leadingEdge < 0)
        #expect(row.trailingEdge > restingWidth)
        #expect(abs(-row.leadingEdge - (row.trailingEdge - restingWidth)) < 1e-9)
    }

    @Test func slotsTileWithoutGapsOrOverlap() {
        let row = DockMagnification.row(icons(6), pointer: 123, peakScale: peak, radius: radius)
        for i in 1 ..< row.origins.count {
            #expect(abs(row.origins[i] - (row.origins[i - 1] + row.widths[i - 1])) < 1e-9)
        }
    }

    @Test func layoutIsContinuousInPointer() {
        let slots = icons(8)
        var previous = DockMagnification.row(slots, pointer: -radius, peakScale: peak, radius: radius)
        for pointer in stride(from: -radius, through: 8 * pitch + radius, by: 0.25) {
            let row = DockMagnification.row(slots, pointer: pointer, peakScale: peak, radius: radius)
            for i in row.origins.indices {
                #expect(abs(row.origins[i] - previous.origins[i]) < 1)
            }
            previous = row
        }
    }

    @Test func rigidSlotsKeepTheirSize() {
        var slots = icons(5)
        slots[2] = .init(width: 120, magnifies: false)
        let row = DockMagnification.row(slots, pointer: 2 * pitch + 60, peakScale: peak, radius: radius)
        #expect(row.scales[2] == 1)
        #expect(row.widths[2] == 120)
        #expect(row.scales[1] > 1)
    }

    @Test func peakOfOneDisablesMagnification() {
        let row = DockMagnification.row(icons(4), pointer: center(of: 1), peakScale: 1, radius: radius)
        #expect(row.scales == [1, 1, 1, 1])
    }

    @Test func maximumOverhangBoundsEveryPointer() {
        let slots = icons(10)
        let overhang = DockMagnification.maximumOverhang(slots, peakScale: peak, radius: radius)
        #expect(overhang.leading > 0)
        #expect(abs(overhang.leading - overhang.trailing) < 0.5)
        // Never more than the whole effect's width on one side.
        #expect(overhang.leading <= (peak - 1) * radius + pitch)
        for pointer in stride(from: -radius, through: 10 * pitch + radius, by: 3.1) {
            let row = DockMagnification.row(slots, pointer: pointer, peakScale: peak, radius: radius)
            #expect(-row.leadingEdge <= overhang.leading + 0.5)
            #expect(row.trailingEdge - 10 * pitch <= overhang.trailing + 0.5)
        }
    }
}

@Suite("Magnification settings")
struct MagnificationSettingsTests {
    @Test func oldFilesGetDefaultMagnification() throws {
        let json = #"{"iconSize": 48, "hoverEffect": true}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(DockSettings.self, from: json)
        #expect(settings.magnification == DockSettings.default.magnification)
        #expect(settings.peakMagnification == DockSettings.default.magnification)
    }

    @Test func outOfRangeValuesAreClamped() throws {
        let tooBig = try JSONDecoder().decode(DockSettings.self, from: Data(#"{"magnification": 9}"#.utf8))
        #expect(tooBig.magnification == DockSettings.magnificationRange.upperBound)
        let tooSmall = try JSONDecoder().decode(DockSettings.self, from: Data(#"{"magnification": 0.2}"#.utf8))
        #expect(tooSmall.magnification == DockSettings.magnificationRange.lowerBound)
    }

    @Test func wrongTypeFallsBackToDefault() throws {
        let settings = try JSONDecoder().decode(DockSettings.self, from: Data(#"{"magnification": "big", "iconSize": 40}"#.utf8))
        #expect(settings.magnification == DockSettings.default.magnification)
        #expect(settings.iconSize == 40)
    }

    @Test func hoverEffectOffMeansNoMagnification() {
        var settings = DockSettings.default
        settings.hoverEffect = false
        #expect(settings.peakMagnification == 1)
    }

    @Test func roundTrips() throws {
        var settings = DockSettings.default
        settings.magnification = 1.8
        let decoded = try JSONDecoder().decode(DockSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }
}
