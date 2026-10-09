import Foundation
import ScriptedWidgetRuntime
import Testing

@Suite("Scripted tile description")
struct TileTests {
    private func decode(_ json: String, limits: ScriptedWidgetLimits = .default) throws(ScriptedWidgetError)
        -> ScriptedTile
    {
        try ScriptedTile.decode(Data(json.utf8), limits: limits)
    }

    /// The detail of the `.invalidTile` a description fails with, or nil when it decodes.
    private func invalidDetail(_ json: String, limits: ScriptedWidgetLimits = .default) -> String? {
        do {
            _ = try decode(json, limits: limits)
            return nil
        } catch {
            if case let .invalidTile(detail) = error { return detail }
            Issue.record("unexpected error \(error)")
            return nil
        }
    }

    @Test func decodesEveryElementKind() throws {
        let tile = try decode(
            """
            {
              "elements": [
                {"type": "text", "text": "Hi", "style": "secondary", "color": "teal"},
                {"type": "number", "value": 12.5, "fractionDigits": 1, "unit": "%", "label": "CPU"},
                {"type": "progress", "fraction": 0.4, "style": "bar", "color": "#1A2B3C", "label": "Day"},
                {"type": "icon", "symbol": "bolt.fill", "size": "large"},
                {"type": "sparkline", "samples": [0, 0.5, 1], "capacity": 60, "color": "orange"},
                {"type": "row", "spacing": 0.2, "children": [
                  {"type": "spacer"},
                  {"type": "column", "alignment": "center", "children": [{"type": "text", "text": "Deep"}]}
                ]}
              ],
              "refresh": 30, "minWidth": 2.5, "accessibilityLabel": "A tile"
            }
            """)
        #expect(
            tile.elements == [
                .text(ScriptedText("Hi", style: .secondary, color: .named(.teal))),
                .number(ScriptedNumber(value: 12.5, fractionDigits: 1, unit: "%", label: "CPU")),
                .progress(ScriptedProgress(fraction: 0.4, style: .bar, color: .hex("#1A2B3C"), label: "Day")),
                .icon(ScriptedIcon(symbol: "bolt.fill", size: .large)),
                .sparkline(ScriptedSparkline(samples: [0, 0.5, 1], capacity: 60, color: .named(.orange))),
                .row(
                    ScriptedGroup(
                        children: [
                            .spacer,
                            .column(ScriptedGroup(children: [.text(ScriptedText("Deep"))], alignment: .center)),
                        ], spacing: 0.2)),
            ])
        #expect(tile.refresh == 30)
        #expect(tile.minWidth == 2.5)
        #expect(tile.accessibilityLabel == "A tile")
        #expect(tile.elementCount == 9)
        #expect(tile.depth == 3)
    }

    @Test func toleratesWhatItCanAndDefaultsTheRest() throws {
        let tile = try decode(
            """
            {"elements": [
               {"type": "text", "text": "Plain", "style": "huge", "color": "chartreuse", "weight": "bold"},
               {"type": "hologram", "depth": 3},
               {"type": "progress", "fraction": 1.5},
               {"type": "row"}
             ], "refresh": "soon", "minWidth": null, "theme": "dark"}
            """)
        #expect(tile.elements[0] == .text(ScriptedText("Plain")))
        #expect(tile.elements[1] == .unsupported("hologram"))
        #expect(tile.elements[2] == .progress(ScriptedProgress(fraction: 1.5)))
        #expect(tile.elements[3] == .row(ScriptedGroup(children: [])))
        #expect(tile.refresh == nil)
        #expect(tile.minWidth == nil)
        #expect(try decode("{}") == ScriptedTile(elements: []))
    }

    @Test func rejectsMissingOrMistypedRequiredFields() {
        #expect(invalidDetail(#"{"elements": [{"type": "text"}]}"#) == "elements[0] is missing \"text\"")
        #expect(
            invalidDetail(#"{"elements": [{"type": "progress", "fraction": "half"}]}"#)
                == "elements[0].fraction has the wrong type")
        #expect(invalidDetail(#"{"elements": [{"text": "no type"}]}"#) == "elements[0] is missing \"type\"")
        #expect(
            invalidDetail(#"{"elements": [{"type": "row", "children": [{"type": "icon"}]}]}"#)
                == "elements[0].children[0] is missing \"symbol\"")
        #expect(invalidDetail(#"{"elements": "none"}"#) == "elements has the wrong type")
        #expect(invalidDetail("[1, 2]") == "the tile has the wrong type")
        #expect(invalidDetail("{") != nil)
    }

    @Test func parsesColors() {
        #expect(ScriptedColor("teal") == .named(.teal))
        #expect(ScriptedColor("#aabbcc") == .hex("#AABBCC"))
        #expect(ScriptedColor("aabbcc") == nil)
        #expect(ScriptedColor("#abc") == nil)
        #expect(ScriptedColor("#GGHHII") == nil)
        #expect(ScriptedColor("") == nil)
    }

    @Test func enforcesLimits() {
        var limits = ScriptedWidgetLimits()
        limits.maxElements = 3
        limits.maxDepth = 2
        limits.maxTextLength = 5
        limits.maxSparklineSamples = 2
        limits.maxTileBytes = 400
        limits.maxMinWidth = 4

        let text = #"{"type": "text", "text": "ok"}"#
        #expect(
            invalidDetail(#"{"elements": [\#(text), \#(text), \#(text), \#(text)]}"#, limits: limits)
                == "4 elements; the most a tile may have is 3")
        #expect(
            invalidDetail(
                #"{"elements": [{"type": "row", "children": [{"type": "row", "children": [\#(text)]}]}]}"#,
                limits: limits)
                == "rows and columns nest 3 deep; the most allowed is 2")
        #expect(
            invalidDetail(#"{"elements": [{"type": "text", "text": "toolong"}]}"#, limits: limits)
                == "a text is 7 characters; the most allowed is 5")
        #expect(
            invalidDetail(#"{"elements": [{"type": "progress", "fraction": 0, "label": "toolong"}]}"#, limits: limits)
                == "a label is 7 characters; the most allowed is 5")
        #expect(
            invalidDetail(#"{"elements": [{"type": "number", "value": 1, "unit": "toolong"}]}"#, limits: limits)
                == "a label is 7 characters; the most allowed is 5")
        #expect(
            invalidDetail(#"{"elements": [{"type": "sparkline", "samples": [0, 0, 0]}]}"#, limits: limits)
                == "a sparkline has 3 samples; the most allowed is 2")
        #expect(
            invalidDetail(#"{"elements": [], "minWidth": 5}"#, limits: limits)
                == "minWidth should be between 0 and 4 icon widths")
        #expect(
            invalidDetail(#"{"elements": [{"type": "row", "children": [\#(text)]}], "minWidth": 4}"#, limits: limits)
                == nil)

        let big = #"{"elements": [{"type": "text", "text": "\#(String(repeating: "x", count: 500))"}]}"#
        do {
            _ = try decode(big, limits: limits)
            Issue.record("a 500-byte tile passed a 400-byte limit")
        } catch {
            #expect(error == .tileTooLarge(bytes: big.utf8.count, limit: 400))
        }
    }

    @Test func buildsAnAccessibilityLabelFromTheTexts() throws {
        let tile = try decode(
            """
            {"elements": [
               {"type": "icon", "symbol": "sun.max"},
               {"type": "column", "children": [{"type": "text", "text": "21°"}, {"type": "number", "value": 3, "label": "Wind"}]},
               {"type": "progress", "fraction": 0.5, "label": "Half"}
             ]}
            """)
        #expect(tile.defaultAccessibilityLabel == "21°, Wind, Half")
    }

    @Test func errorsDescribeThemselves() {
        #expect(
            ScriptedWidgetError.timedOut(.render, limit: 0.25).description
                == "render() took longer than 250 ms and was stopped.")
        #expect(
            ScriptedWidgetError.timedOut(.load, limit: 2).description
                == "Loading the script took longer than 2 s and was stopped.")
        #expect(ScriptedWidgetError.timedOut(.load, limit: 2).shortDescription == "Timed out")
        #expect(
            ScriptedWidgetError.exception(message: "ReferenceError: x is not defined", line: 12).description
                == "Line 12: ReferenceError: x is not defined")
        #expect(ScriptedWidgetError.exception(message: "boom", line: nil).shortDescription == "Script error")
        #expect(
            ScriptedWidgetError.unreadableFile("main.js", reason: "the file doesn't exist").shortDescription
                == "Can't load")
    }
}
