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
        let anonymous = DockPlacement.Screen(
            id: nil, name: "Projector", frame: laptop.frame, visibleFrame: laptop.visibleFrame)
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
        let frame = DockPlacement.shownFrame(
            contentSize: CGSize(width: 600, height: 160), visibleFrame: below.visibleFrame)
        #expect(frame.minY == -1010)
        #expect(below.frame.contains(frame))
    }

    @Test func shownFrameIsOnWholePoints() {
        let frame = DockPlacement.shownFrame(
            contentSize: CGSize(width: 601, height: 160), visibleFrame: laptop.visibleFrame)
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

    // MARK: - Side edges

    @Test func shownFrameOnTheLeftIsCenteredUpTheVisibleFrame() {
        let size = CGSize(width: 160, height: 600)
        for screen in screens {
            let frame = DockPlacement.shownFrame(contentSize: size, visibleFrame: screen.visibleFrame, edge: .left)
            #expect(frame.size == size)
            #expect(frame.minX == screen.visibleFrame.minX, "\(screen.name)")
            #expect(abs(frame.midY - screen.visibleFrame.midY) <= 0.5, "\(screen.name)")
            #expect(frame.minY == frame.minY.rounded())
        }
    }

    @Test func shownFrameOnTheRightTouchesTheRightOfTheVisibleFrame() {
        let size = CGSize(width: 160, height: 600)
        for screen in screens {
            let frame = DockPlacement.shownFrame(contentSize: size, visibleFrame: screen.visibleFrame, edge: .right)
            #expect(frame.size == size)
            #expect(frame.maxX == screen.visibleFrame.maxX, "\(screen.name)")
            #expect(abs(frame.midY - screen.visibleFrame.midY) <= 0.5, "\(screen.name)")
        }
    }

    /// Apple's Dock on the same side leaves a visible frame that doesn't start at the
    /// display's edge; OpenDock sits inside it, not behind the Dock.
    @Test func shownFrameOnASideStaysInsideTheVisibleFrame() {
        let withDock = DockPlacement.Screen(
            id: "DOCKED", name: "Docked",
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 70, y: 0, width: 1442, height: 949))
        let size = CGSize(width: 160, height: 600)
        let frame = DockPlacement.shownFrame(contentSize: size, visibleFrame: withDock.visibleFrame, edge: .left)
        #expect(frame.minX == 70)
        #expect(withDock.visibleFrame.contains(frame))
    }

    @Test func oversizedSideWindowIsClampedToItsDisplay() {
        let size = CGSize(width: 1800, height: 1200)
        for edge in [DockSettings.Edge.left, .right] {
            let frame = DockPlacement.shownFrame(contentSize: size, visibleFrame: laptop.visibleFrame, edge: edge)
            #expect(frame == laptop.visibleFrame, "\(edge)")
        }
    }

    @Test func hiddenSideFramesAreJustPastThePhysicalEdge() {
        let size = CGSize(width: 160, height: 600)
        for screen in screens {
            let shownLeft = DockPlacement.shownFrame(contentSize: size, visibleFrame: screen.visibleFrame, edge: .left)
            let hiddenLeft = DockPlacement.hiddenFrame(contentSize: size, on: screen, edge: .left)
            #expect(hiddenLeft.maxX < screen.frame.minX, "\(screen.name)")
            #expect(hiddenLeft.minY == shownLeft.minY)
            #expect(hiddenLeft.size == shownLeft.size)

            let shownRight = DockPlacement.shownFrame(
                contentSize: size, visibleFrame: screen.visibleFrame, edge: .right)
            let hiddenRight = DockPlacement.hiddenFrame(contentSize: size, on: screen, edge: .right)
            #expect(hiddenRight.minX > screen.frame.maxX, "\(screen.name)")
            #expect(hiddenRight.minY == shownRight.minY)
            #expect(hiddenRight.size == shownRight.size)
        }
    }

    @Test func bottomIsTheDefaultEdgeForEveryFrame() {
        let size = CGSize(width: 600, height: 160)
        #expect(
            DockPlacement.shownFrame(contentSize: size, visibleFrame: laptop.visibleFrame)
                == DockPlacement.shownFrame(contentSize: size, visibleFrame: laptop.visibleFrame, edge: .bottom))
        #expect(
            DockPlacement.hiddenFrame(contentSize: size, on: laptop)
                == DockPlacement.hiddenFrame(contentSize: size, on: laptop, edge: .bottom))
    }

    @Test func revealEdgeOnTheLeftIsTheDisplaysLeftColumn() {
        #expect(DockPlacement.isAtRevealEdge(CGPoint(x: 0, y: 500), of: laptop.frame, edge: .left))
        #expect(DockPlacement.isAtRevealEdge(CGPoint(x: 0.5, y: 500), of: laptop.frame, edge: .left))
        #expect(DockPlacement.isAtRevealEdge(CGPoint(x: -2560, y: 700), of: left.frame, edge: .left))
        #expect(!DockPlacement.isAtRevealEdge(CGPoint(x: 3, y: 500), of: laptop.frame, edge: .left))
        // The display to the left shares the edge's x but isn't this display.
        #expect(!DockPlacement.isAtRevealEdge(CGPoint(x: -10, y: 500), of: laptop.frame, edge: .left))
        #expect(!DockPlacement.isAtRevealEdge(CGPoint(x: 0, y: 1000), of: laptop.frame, edge: .left))
        #expect(!DockPlacement.isAtRevealEdge(CGPoint(x: 0, y: -500), of: laptop.frame, edge: .left))
    }

    @Test func revealEdgeOnTheRightIsTheDisplaysLastColumn() {
        // The pointer stops on the last pixel column, at maxX - 1.
        #expect(DockPlacement.isAtRevealEdge(CGPoint(x: 1511, y: 500), of: laptop.frame, edge: .right))
        #expect(DockPlacement.isAtRevealEdge(CGPoint(x: 1511.5, y: 500), of: laptop.frame, edge: .right))
        #expect(DockPlacement.isAtRevealEdge(CGPoint(x: -1, y: 700), of: left.frame, edge: .right))
        #expect(!DockPlacement.isAtRevealEdge(CGPoint(x: 1508, y: 500), of: laptop.frame, edge: .right))
        // Past the edge, onto the laptop that sits to the right of the left display.
        #expect(!DockPlacement.isAtRevealEdge(CGPoint(x: 10, y: 700), of: left.frame, edge: .right))
        #expect(!DockPlacement.isAtRevealEdge(CGPoint(x: 1511, y: -100), of: laptop.frame, edge: .right))
    }

    @Test func sideEdgesDoNotRevealFromTheBottom() {
        #expect(!DockPlacement.isAtRevealEdge(CGPoint(x: 700, y: 0), of: laptop.frame, edge: .left))
        #expect(!DockPlacement.isAtRevealEdge(CGPoint(x: 700, y: 0), of: laptop.frame, edge: .right))
        #expect(!DockPlacement.isAtRevealEdge(CGPoint(x: 0, y: 500), of: laptop.frame, edge: .bottom))
    }

    @Test func hitZoneReachesTheScreenEdgeOnEverySide() {
        let zone = CGRect(x: 20, y: 20, width: 100, height: 100)
        let bottom = DockPlacement.reachingScreenEdge(zone, of: laptop.frame, edge: .bottom)
        #expect(bottom == CGRect(x: 20, y: 0, width: 100, height: 120))
        let left = DockPlacement.reachingScreenEdge(zone, of: laptop.frame, edge: .left)
        #expect(left == CGRect(x: 0, y: 20, width: 120, height: 100))
        let right = DockPlacement.reachingScreenEdge(zone, of: laptop.frame, edge: .right)
        #expect(right == CGRect(x: 20, y: 20, width: 1492, height: 100))
    }

    @Test func hitZoneAlreadyPastTheEdgeIsLeftAlone() {
        let zone = CGRect(x: -5, y: -5, width: 100, height: 100)
        #expect(DockPlacement.reachingScreenEdge(zone, of: laptop.frame, edge: .bottom) == zone)
        #expect(DockPlacement.reachingScreenEdge(zone, of: laptop.frame, edge: .left) == zone)
        let atRight = CGRect(x: 1420, y: 0, width: 100, height: 100)
        #expect(DockPlacement.reachingScreenEdge(atRight, of: laptop.frame, edge: .right) == atRight)
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
        #expect(
            try decode(#"{"display": {"kind": "specific", "id": "ABC"}}"#).display == .specific(id: "ABC", name: ""))
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
