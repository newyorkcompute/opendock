import CoreGraphics
import Foundation
import Testing
@testable import DockCore

@Suite("Dock placement across displays")
struct PlacementTests {
    /// A 1512x982 laptop as the main display, with the menu bar on top.
    private let laptop = DockPlacement.Screen(
        id: "LAPTOP",
        name: "Built-in Retina Display",
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949)
    )
    /// A 2560x1440 external display arranged to the left of the laptop, bottoms aligned.
    private let left = DockPlacement.Screen(
        id: "LEFT",
        name: "Studio Display",
        frame: CGRect(x: -2560, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: -2560, y: 0, width: 2560, height: 1415)
    )
    /// A 1920x1080 display arranged below the laptop. Apple's Dock is on it.
    private let below = DockPlacement.Screen(
        id: "BELOW",
        name: "DELL U2720Q",
        frame: CGRect(x: -204, y: -1080, width: 1920, height: 1080),
        visibleFrame: CGRect(x: -204, y: -1010, width: 1920, height: 1010)
    )

    private var screens: [DockPlacement.Screen] { [laptop, left, below] }

    // MARK: - Choosing a display

    @Test func mainIsTheFirstScreen() {
        #expect(DockPlacement.screenIndex(for: .main, in: screens, activeIndex: 2) == 0)
    }

    @Test func activeFollowsTheActiveDisplay() {
        #expect(DockPlacement.screenIndex(for: .active, in: screens, activeIndex: 1) == 1)
        #expect(DockPlacement.screenIndex(for: .active, in: screens, activeIndex: 2) == 2)
    }

    @Test func activeFallsBackToMainWhenUnknown() {
        #expect(DockPlacement.screenIndex(for: .active, in: screens, activeIndex: nil) == 0)
        #expect(DockPlacement.screenIndex(for: .active, in: screens, activeIndex: 7) == 0)
    }

    @Test func specificFindsItsDisplayWhereverItIsListed() {
        let choice = DockSettings.Display.specific(id: "BELOW", name: "DELL U2720Q")
        #expect(DockPlacement.screenIndex(for: choice, in: screens, activeIndex: nil) == 2)
        // Rearranged, or another display unplugged: still found by ID.
        #expect(DockPlacement.screenIndex(for: choice, in: [laptop, below], activeIndex: nil) == 1)
    }

    @Test func specificFallsBackToMainWhileUnplugged() {
        let choice = DockSettings.Display.specific(id: "LEFT", name: "Studio Display")
        #expect(DockPlacement.screenIndex(for: choice, in: [laptop, below], activeIndex: 1) == 0)
        // The main display changed while it was away.
        #expect(DockPlacement.screenIndex(for: choice, in: [below, laptop], activeIndex: nil) == 0)
    }

    @Test func specificNeverMatchesScreensWithoutAnID() {
        let anonymous = DockPlacement.Screen(id: nil, name: "Projector", frame: laptop.frame, visibleFrame: laptop.visibleFrame)
        let choice = DockSettings.Display.specific(id: "LEFT", name: "")
        #expect(DockPlacement.screenIndex(for: choice, in: [laptop, anonymous], activeIndex: nil) == 0)
    }

    @Test func noScreensMeansNoPlacement() {
        #expect(DockPlacement.screenIndex(for: .main, in: [], activeIndex: nil) == nil)
        #expect(DockPlacement.screenIndex(for: .active, in: [], activeIndex: 0) == nil)
        #expect(DockPlacement.screenIndex(for: .specific(id: "LAPTOP", name: ""), in: [], activeIndex: nil) == nil)
    }

    // MARK: - Frames

    @Test func shownFrameIsBottomCenterOfVisibleFrame() {
        let size = CGSize(width: 600, height: 160)
        for screen in screens {
            let frame = DockPlacement.shownFrame(contentSize: size, visibleFrame: screen.visibleFrame)
            #expect(frame.size == size)
            #expect(frame.minY == screen.visibleFrame.minY, "\(screen.name)")
            #expect(abs(frame.midX - screen.visibleFrame.midX) <= 0.5, "\(screen.name)")
        }
    }

    @Test func shownFrameSitsAboveAppleDock() {
        let frame = DockPlacement.shownFrame(contentSize: CGSize(width: 600, height: 160), visibleFrame: below.visibleFrame)
        #expect(frame.minY == -1010)
        #expect(below.frame.contains(frame))
    }

    @Test func shownFrameIsOnWholePoints() {
        let frame = DockPlacement.shownFrame(contentSize: CGSize(width: 601, height: 160), visibleFrame: laptop.visibleFrame)
        #expect(frame.minX == frame.minX.rounded())
    }

    /// The window is wider than the dock (magnification overhang on both sides). When it
    /// doesn't fit, it's trimmed evenly so it stays centered and never reaches onto the
    /// neighboring display.
    @Test func oversizedWindowIsClampedToItsDisplay() {
        let size = CGSize(width: 1800, height: 1200)
        let frame = DockPlacement.shownFrame(contentSize: size, visibleFrame: laptop.visibleFrame)
        #expect(frame == laptop.visibleFrame)
        #expect(laptop.frame.contains(frame))
    }

    @Test func hiddenFrameIsJustBelowThePhysicalEdge() {
        let size = CGSize(width: 600, height: 160)
        for screen in screens {
            let shown = DockPlacement.shownFrame(contentSize: size, visibleFrame: screen.visibleFrame)
            let hidden = DockPlacement.hiddenFrame(contentSize: size, on: screen)
            #expect(hidden.maxY < screen.frame.minY, "\(screen.name)")
            #expect(hidden.minX == shown.minX)
            #expect(hidden.size == shown.size)
        }
    }

    // MARK: - Reveal edge

    @Test func revealEdgeIsTheDisplaysBottomRow() {
        #expect(DockPlacement.isAtRevealEdge(CGPoint(x: 700, y: 0), of: laptop.frame))
        #expect(DockPlacement.isAtRevealEdge(CGPoint(x: 700, y: 1), of: laptop.frame))
        #expect(DockPlacement.isAtRevealEdge(CGPoint(x: -1000, y: 0.5), of: left.frame))
        #expect(DockPlacement.isAtRevealEdge(CGPoint(x: 0, y: -1080), of: below.frame))
        #expect(!DockPlacement.isAtRevealEdge(CGPoint(x: 700, y: 3), of: laptop.frame))
    }

    @Test func revealEdgeIgnoresOtherDisplays() {
        // Anywhere on the display below the laptop is "lower" than the laptop's edge.
        #expect(!DockPlacement.isAtRevealEdge(CGPoint(x: 700, y: -500), of: laptop.frame))
        #expect(!DockPlacement.isAtRevealEdge(CGPoint(x: 700, y: -1080), of: laptop.frame))
        // The neighbor to the left shares the bottom edge's y but not its x range.
        #expect(!DockPlacement.isAtRevealEdge(CGPoint(x: -10, y: 0), of: laptop.frame))
        #expect(!DockPlacement.isAtRevealEdge(CGPoint(x: 0, y: 0), of: left.frame))
    }
}

@Suite("Display setting persistence")
struct DisplaySettingTests {
    private func decode(_ json: String) throws -> DockSettings {
        try JSONDecoder().decode(DockSettings.self, from: Data(json.utf8))
    }

    @Test func missingKeyMeansMainDisplay() throws {
        #expect(try decode(#"{"iconSize": 40}"#).display == .main)
        #expect(DockSettings.default.display == .main)
    }

    @Test func roundTripsEveryChoice() throws {
        let choices: [DockSettings.Display] = [
            .main,
            .active,
            .specific(id: "37D8832A-2D66-02CA-B9F7-8F30A301B230", name: "DELL U2720Q"),
        ]
        for choice in choices {
            var settings = DockSettings.default
            settings.display = choice
            let decoded = try JSONDecoder().decode(DockSettings.self, from: JSONEncoder().encode(settings))
            #expect(decoded == settings)
        }
    }

    @Test func decodesTheStoredShape() throws {
        let settings = try decode(#"{"display": {"kind": "specific", "id": "ABC", "name": "Studio Display"}}"#)
        #expect(settings.display == .specific(id: "ABC", name: "Studio Display"))
        #expect(try decode(#"{"display": {"kind": "active"}}"#).display == .active)
    }

    @Test func specificWithoutNameKeepsTheID() throws {
        #expect(try decode(#"{"display": {"kind": "specific", "id": "ABC"}}"#).display == .specific(id: "ABC", name: ""))
    }

    @Test func unrecognizedValuesFallBackWithoutLosingOtherSettings() throws {
        let bad = [
            #"{"display": {"kind": "hologram"}, "iconSize": 40}"#,
            #"{"display": {"kind": "specific"}, "iconSize": 40}"#,
            #"{"display": {"kind": "specific", "id": ""}, "iconSize": 40}"#,
            #"{"display": "main", "iconSize": 40}"#,
            #"{"display": 3, "iconSize": 40}"#,
            #"{"display": null, "iconSize": 40}"#,
        ]
        for json in bad {
            let settings = try decode(json)
            #expect(settings.display == .main, "\(json)")
            #expect(settings.iconSize == 40, "\(json)")
        }
    }
}
