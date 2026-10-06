import CoreGraphics
import Foundation
import Testing
@testable import DockCore

@Suite("Dock magnification geometry")
struct MagnificationTests {
    private let pitch = 54.0
    private let peak = 1.5
    private var radius: Double { 3 * pitch }

    private func icons(_ count: Int) -> [DockMagnification.Slot] {
        Array(repeating: .init(width: pitch, growth: 1), count: count)
    }

    private func center(of index: Int) -> Double { (Double(index) + 0.5) * pitch }

    @Test func falloffMatchesAppleDock() {
        // Measured from the Dock's accessibility frames, in resting slots from the pointer.
        let measured: [(slots: Double, value: Double)] = [
            (0.5, 0.965), (1, 0.866), (1.5, 0.708), (2, 0.50), (2.5, 0.26), (3, 0.067), (3.5, 0),
        ]
        for point in measured {
            let value = DockMagnification.falloff(distance: point.slots, radius: DockMagnification.dockRadiusInSlots)
            #expect(abs(value - point.value) < 0.03, "at \(point.slots) slots: \(value) vs \(point.value)")
        }
    }

    @Test func falloffIsSmoothBell() {
        #expect(DockMagnification.falloff(distance: 0, radius: 100) == 1)
        #expect(DockMagnification.falloff(distance: 20, radius: 100) > DockMagnification.falloff(distance: 40, radius: 100))
        #expect(DockMagnification.falloff(distance: -50, radius: 100) == DockMagnification.falloff(distance: 50, radius: 100))
        #expect(DockMagnification.falloff(distance: 100, radius: 100) == 0)
        #expect(DockMagnification.falloff(distance: 250, radius: 100) == 0)
        // Zero slope at the edge: no visible "pop" as an item enters the range.
        #expect(DockMagnification.falloff(distance: 99, radius: 100) < 0.01)
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
        slots[2] = .init(width: 120, growth: 0)
        let row = DockMagnification.row(slots, pointer: 2 * pitch + 60, peakScale: peak, radius: radius)
        #expect(row.scales[2] == 1)
        #expect(row.widths[2] == 120)
        #expect(row.scales[1] > 1)
    }

    // MARK: Widgets

    /// Icons around a widget tile three icon pitches wide, like the Calendar tile with an event.
    private func iconsAroundWidget(width: Double = 3 * 54) -> [DockMagnification.Slot] {
        var slots = icons(6)
        slots.insert(.init(width: width, growth: DockMagnification.widgetGrowth), at: 3)
        return slots
    }

    @Test(arguments: [1.2, 1.5, 2.0])
    func widgetPeakIsDampedInProportionToTheSetting(peak: Double) {
        let slots = iconsAroundWidget()
        let widgetCenter = 3 * pitch + slots[3].width / 2
        let row = DockMagnification.row(slots, pointer: widgetCenter, peakScale: peak, radius: radius)
        #expect(abs(row.scales[3] - (1 + DockMagnification.widgetGrowth * (peak - 1))) < 1e-12)
        #expect(row.scales[3] < peak)
    }

    @Test func widgetPeakAtDefaultSettingIs115() {
        let peak = DockSettings.default.peakMagnification
        let widget = [DockMagnification.Slot(width: 120, growth: DockMagnification.widgetGrowth)]
        let row = DockMagnification.row(widget, pointer: 60, peakScale: peak, radius: radius)
        #expect(abs(row.scales[0] - 1.15) < 1e-9)
    }

    @Test func widgetFollowsTheSameFalloffAsIcons() {
        let slots = iconsAroundWidget()
        let widgetCenter = 3 * pitch + slots[3].width / 2
        for offset in stride(from: -200.0, through: 200, by: 25) {
            let row = DockMagnification.row(slots, pointer: widgetCenter + offset, peakScale: peak, radius: radius)
            let expected = 1 + DockMagnification.widgetGrowth * (peak - 1) * DockMagnification.falloff(distance: offset, radius: radius)
            #expect(abs(row.scales[3] - expected) < 1e-9, "at \(offset): \(row.scales[3]) vs \(expected)")
        }
    }

    @Test func wideWidgetPushesNeighborsNoFurtherThanOneIcon() {
        // At full effect a tile three pitches wide grows less than one icon does.
        let widget = DockMagnification.row(iconsAroundWidget(), pointer: 3 * pitch + 1.5 * pitch, peakScale: 2, radius: radius)
        let icon = DockMagnification.row(icons(9), pointer: center(of: 4), peakScale: 2, radius: radius)
        #expect(widget.widths[3] - 3 * pitch < icon.widths[4] - pitch)
    }

    @Test func pointStaysUnderPointerOverWidgets() {
        let slots = iconsAroundWidget()
        let restingWidth = slots.reduce(0) { $0 + $1.width }
        var origins: [Double] = []
        var x = 0.0
        for slot in slots {
            origins.append(x)
            x += slot.width
        }
        for pointer in stride(from: 0.0, through: restingWidth - 0.1, by: 6.7) {
            let row = DockMagnification.row(slots, pointer: pointer, peakScale: peak, radius: radius)
            guard let k = row.slotIndex(at: pointer) else {
                Issue.record("pointer \(pointer) not inside any slot")
                continue
            }
            let restingFraction = (pointer - origins[k]) / slots[k].width
            let magnifiedFraction = (pointer - row.origins[k]) / row.widths[k]
            #expect(abs(restingFraction - magnifiedFraction) < 1e-9)
        }
    }

    @Test func maximumOverhangIncludesWidgetGrowth() {
        let widgets = Array(repeating: DockMagnification.Slot(width: 120, growth: DockMagnification.widgetGrowth), count: 3)
        let overhang = DockMagnification.maximumOverhang(widgets, peakScale: peak, radius: radius)
        #expect(overhang.leading > 0 && overhang.trailing > 0)
        let mixed = iconsAroundWidget()
        let mixedWidth = mixed.reduce(0) { $0 + $1.width }
        let mixedOverhang = DockMagnification.maximumOverhang(mixed, peakScale: peak, radius: radius)
        for pointer in stride(from: -radius, through: mixedWidth + radius, by: 2.9) {
            let row = DockMagnification.row(mixed, pointer: pointer, peakScale: peak, radius: radius)
            #expect(-row.leadingEdge <= mixedOverhang.leading + 0.5)
            #expect(row.trailingEdge - mixedWidth <= mixedOverhang.trailing + 0.5)
        }
    }

    @Test func growthByItemKind() {
        #expect(DockMagnification.growth(for: .app(at: URL(filePath: "/Applications/Safari.app"))) == 1)
        #expect(DockMagnification.growth(for: .folder(at: URL(filePath: "/Users/me/Downloads"))) == 1)
        #expect(DockMagnification.growth(for: .spacer()) == 1)
        #expect(DockMagnification.growth(for: .widget("com.example.widget")) == DockMagnification.widgetGrowth)
        #expect(DockMagnification.growth(for: .divider()) == 0)
    }

    @Test func growthIsClamped() {
        #expect(DockMagnification.Slot(width: 10, growth: 3).growth == 1)
        #expect(DockMagnification.Slot(width: 10, growth: -1).growth == 0)
    }

    // MARK: Item sizes

    @Test func iconsGrowSquareAndKeepTheirIndicatorRoom() {
        let icon = CGSize(width: 48, height: 54)
        let size = DockMagnification.itemSize(icon, scale: 1.5, iconSize: 48)
        #expect(size == CGSize(width: 72, height: 78))
    }

    @Test func widgetsGrowInHeightLikeAnIconAndInWidthLikeTheirSlot() {
        let tile = CGSize(width: 150, height: 54)
        let size = DockMagnification.itemSize(tile, scale: 1.15, iconSize: 48)
        #expect(abs(size.width - 150 * 1.15) < 1e-9)
        #expect(abs(size.height - (54 + 48 * 0.15)) < 1e-9)
        // The tile's own height, without the indicator room, is the icon size times the scale.
        #expect(abs(DockMagnification.tileScale(height: size.height - 6, iconSize: 48) - 1.15) < 1e-9)
    }

    @Test func restingSizeIsUnchanged() {
        let tile = CGSize(width: 150, height: 54)
        #expect(DockMagnification.itemSize(tile, scale: 1, iconSize: 48) == tile)
        #expect(DockMagnification.tileScale(height: 48, iconSize: 48) == 1)
        #expect(DockMagnification.tileScale(height: 48.01, iconSize: 48) == 1)
        #expect(DockMagnification.tileScale(height: 0, iconSize: 48) == 1)
        #expect(DockMagnification.tileScale(height: 40, iconSize: 48) == 1)
    }

    // MARK: Resting size of re-laid-out tiles

    @Test func restingSizeIsKeptWhileMagnified() {
        var tracker = DockMagnification.RestingSizeTracker()
        let resting = CGSize(width: 100, height: 48)
        #expect(tracker.update(natural: resting, scale: 1) == resting)
        // Laid out again at 1.1× and 1.15×; text doesn't scale exactly in proportion.
        #expect(tracker.update(natural: CGSize(width: 111, height: 52.8), scale: 1.1) == resting)
        #expect(tracker.update(natural: CGSize(width: 116, height: 55.2), scale: 1.15) == resting)
        #expect(tracker.update(natural: CGSize(width: 116, height: 55.2), scale: 1.15) == resting)
        #expect(tracker.update(natural: resting, scale: 1) == resting)
    }

    @Test func contentChangesWhileMagnifiedAreTracked() {
        var tracker = DockMagnification.RestingSizeTracker()
        _ = tracker.update(natural: CGSize(width: 100, height: 48), scale: 1)
        _ = tracker.update(natural: CGSize(width: 115, height: 55.2), scale: 1.15)
        // The clock ticked over to a wider time at the same scale.
        let wider = tracker.update(natural: CGSize(width: 138, height: 55.2), scale: 1.15)
        #expect(abs(wider.width - 120) < 1e-9)
        #expect(abs(wider.height - 48) < 1e-9)
        // Back at rest, the natural size is the resting size again.
        #expect(tracker.update(natural: CGSize(width: 121, height: 48), scale: 1) == CGSize(width: 121, height: 48))
    }

    @Test func firstMeasurementWhileMagnifiedIsUnscaled() {
        var tracker = DockMagnification.RestingSizeTracker()
        let resting = tracker.update(natural: CGSize(width: 120, height: 60), scale: 1.2)
        #expect(abs(resting.width - 100) < 1e-9)
        #expect(abs(resting.height - 50) < 1e-9)
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
