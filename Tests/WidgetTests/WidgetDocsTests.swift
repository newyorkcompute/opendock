import BuiltInWidgets
import DockCore
import DockWidgetKit
import Foundation
import Testing

/// `docs/widgets.md` is generated from the built-in widgets' settings schemas. This fails
/// when the two drift apart; `make widget-docs` rewrites the generated section.
@MainActor
@Suite("Widget docs")
struct WidgetDocsTests {
    private static let docsURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // WidgetTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
        .appendingPathComponent("docs/widgets.md")

    private static let updateEnvironmentKey = "OPENDOCK_UPDATE_WIDGET_DOCS"

    private var entries: [WidgetDocs.Entry] {
        BuiltInWidgets.all.map {
            WidgetDocs.Entry(
                typeID: $0.typeID, displayName: $0.displayName, summary: $0.summary, schema: $0.settingsSchema)
        }
    }

    @Test func generatedSectionMatchesSchemas() throws {
        let expected = WidgetDocs.generatedSection(for: entries)
        var document = try String(contentsOf: Self.docsURL, encoding: .utf8)

        if ProcessInfo.processInfo.environment[Self.updateEnvironmentKey] == "1" {
            document = try #require(
                WidgetDocs.replacingGeneratedSection(in: document, with: expected),
                "docs/widgets.md has no generated section markers")
            try document.write(to: Self.docsURL, atomically: true, encoding: .utf8)
        }

        let actual = try #require(
            WidgetDocs.generatedSection(in: document), "docs/widgets.md has no generated section markers")
        #expect(
            actual == expected,
            "docs/widgets.md is out of date with the widgets' settings schemas. Run `make widget-docs` and commit the result."
        )
    }

    @Test func everyBuiltInWidgetIsDocumented() throws {
        let document = try String(contentsOf: Self.docsURL, encoding: .utf8)
        for widget in BuiltInWidgets.all {
            #expect(document.contains("`\(widget.typeID)`"), "\(widget.displayName) is missing from docs/widgets.md")
        }
    }

    @Test func rendersEveryValueType() {
        #expect(WidgetDocs.describe(.bool) == "`\"true\"` or `\"false\"`")
        #expect(WidgetDocs.describe(.choice(["a", "b", "c"])) == "One of `\"a\"`, `\"b\"`, or `\"c\"`")
        #expect(WidgetDocs.describe(.integer(1 ... 9)) == "A whole number from 1 to 9")
        #expect(WidgetDocs.describe(.number(-90 ... 90)) == "A number from -90 to 90")
        #expect(WidgetDocs.describe(.number(0 ... 0.5)) == "A number from 0 to 0.5")
        #expect(WidgetDocs.describe(.text) == "Any text")
    }

    @Test func replacesOnlyTheGeneratedSection() throws {
        let before = "intro\n\n\(WidgetDocs.beginMarker)\nold\n\(WidgetDocs.endMarker)\n\nnotes\n"
        let section = "\(WidgetDocs.beginMarker)\nnew\n\(WidgetDocs.endMarker)\n"
        let after = try #require(WidgetDocs.replacingGeneratedSection(in: before, with: section))
        #expect(after == "intro\n\n\(WidgetDocs.beginMarker)\nnew\n\(WidgetDocs.endMarker)\n\nnotes\n")
        #expect(WidgetDocs.generatedSection(in: after) == section)
        #expect(WidgetDocs.replacingGeneratedSection(in: "no markers", with: section) == nil)
    }
}
