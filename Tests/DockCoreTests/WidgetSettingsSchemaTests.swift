import Foundation
import Testing

@testable import DockCore

@Suite("Widget settings schema")
struct WidgetSettingsSchemaTests {
    private let flag = WidgetSettingKey("flag", type: .bool, default: "true", summary: "A flag.")
    private let style = WidgetSettingKey(
        "style", type: .choice(["digital", "analog"]), default: "digital", summary: "")
    private let count = WidgetSettingKey("count", type: .integer(1 ... 5), default: "3", summary: "")
    private let zone = WidgetSettingKey("zone", type: .timeZone, default: "", summary: "")
    private let note = WidgetSettingKey("note", type: .text, default: "", summary: "")
    private let latitude = WidgetSettingKey("latitude", type: .number(-90 ... 90), default: "", summary: "")

    private var schema: WidgetSettingsSchema { WidgetSettingsSchema([flag, style, count, zone, note, latitude]) }

    @Test func boolAcceptsOnlyTrueAndFalse() {
        #expect(flag.isValid("true"))
        #expect(flag.isValid("false"))
        #expect(!flag.isValid("yes"))
        #expect(!flag.isValid("TRUE"))
        #expect(!flag.isValid(""))
    }

    @Test func choiceAcceptsListedValues() {
        #expect(style.isValid("analog"))
        #expect(!style.isValid("Analog"))
        #expect(!style.isValid(""))
    }

    @Test func integerAcceptsDecimalInRange() {
        #expect(count.isValid("1"))
        #expect(count.isValid("5"))
        #expect(!count.isValid("0"))
        #expect(!count.isValid("6"))
        #expect(!count.isValid("2.5"))
        #expect(!count.isValid("two"))
    }

    @Test func numberAcceptsDecimalInRange() {
        #expect(latitude.isValid("59.91"))
        #expect(latitude.isValid("-90"))
        #expect(latitude.isValid("1e1"))
        #expect(!latitude.isValid("90.5"))
        #expect(!latitude.isValid("nan"))
        #expect(!latitude.isValid("inf"))
        #expect(!latitude.isValid("north"))
        #expect(latitude.doubleValue(in: ["latitude": "12.5"]) == 12.5)
        #expect(latitude.doubleValue(in: ["latitude": "120"]) == nil)
        #expect(latitude.doubleValue(in: [:]) == nil)
    }

    @Test func defaultIsAlwaysValid() {
        // An optional number or choice can default to "" for "not set".
        #expect(latitude.isValid(""))
        let unit = WidgetSettingKey("unit", type: .choice(["c", "f"]), default: "", summary: "")
        #expect(unit.isValid(""))
        #expect(unit.isValid("c"))
        #expect(!unit.isValid("k"))
        #expect(unit.value(in: ["unit": "k"]) == "")
    }

    @Test func timeZoneAcceptsEmptyOrKnownIdentifier() {
        #expect(zone.isValid(""))
        #expect(zone.isValid("Europe/Oslo"))
        #expect(!zone.isValid("Mars/Olympus_Mons"))
    }

    @Test func textAcceptsAnything() {
        #expect(note.isValid(""))
        #expect(note.isValid("anything at all, even \"quotes\""))
    }

    @Test func readingFallsBackToDefault() {
        #expect(flag.boolValue(in: [:]))
        #expect(flag.boolValue(in: ["flag": "maybe"]))
        #expect(!flag.boolValue(in: ["flag": "false"]))
        #expect(count.intValue(in: ["count": "4"]) == 4)
        #expect(count.intValue(in: ["count": "40"]) == 3)
        #expect(style.value(in: ["style": "cuckoo"]) == "digital")
        #expect(style.value(in: ["style": "analog"]) == "analog")
    }

    @Test func defaultsCoverEveryKey() {
        #expect(
            schema.defaults == [
                "flag": "true", "style": "digital", "count": "3", "zone": "", "note": "", "latitude": "",
            ])
        #expect(schema.key(named: "count")?.defaultValue == "3")
        #expect(schema.key(named: "missing") == nil)
    }

    @Test func sanitizedReplacesOnlyInvalidValues() {
        let settings = [
            "flag": "sometimes",
            "style": "analog",
            "count": "99",
            "zone": "Nowhere/Special",
            "note": "keep me",
            "latitude": "95",
            "futureKey": "from a newer build",
        ]
        let cleaned = schema.sanitized(settings)
        #expect(
            cleaned == [
                "flag": "true",
                "style": "analog",
                "count": "3",
                "zone": "",
                "note": "keep me",
                "latitude": "",
                "futureKey": "from a newer build",
            ])
        #expect(schema.invalidKeys(in: settings).map(\.name) == ["flag", "count", "zone", "latitude"])
    }

    @Test func sanitizedLeavesMissingKeysMissing() {
        #expect(schema.sanitized([:]).isEmpty)
        #expect(schema.sanitized(["note": "x"]) == ["note": "x"])
    }
}

@Suite("Widget settings validation on load")
struct WidgetSettingsLoadTests {
    private let clockSchema = WidgetSettingsSchema([
        WidgetSettingKey("showSeconds", type: .bool, default: "false", summary: ""),
        WidgetSettingKey("timeZone", type: .timeZone, default: "", summary: ""),
    ])
    private var schemas: [String: WidgetSettingsSchema] { [BuiltInWidgetID.clock: clockSchema] }

    private func document() -> DockDocument {
        let work = DockProfile(
            name: "Work",
            items: [
                .widget(BuiltInWidgetID.clock, settings: ["showSeconds": "maybe", "timeZone": "Europe/Oslo"]),
                .widget(BuiltInWidgetID.battery, settings: ["showPercentage": "maybe"]),
            ])
        let home = DockProfile(
            name: "Home",
            items: [
                .spacer(),
                .widget(BuiltInWidgetID.clock, settings: ["timeZone": "Atlantis/Lost", "color": "teal"]),
            ])
        return DockDocument(profiles: [work, home], activeProfileID: work.id)
    }

    private func settings(_ document: DockDocument) -> [[[String: String]]] {
        document.profiles.map { $0.items.compactMap(\.widgetInstance?.settings) }
    }

    @Test func decodeResetsInvalidValuesInEveryProfile() throws {
        let data = try DockStorage.encode(document())
        let loaded = try DockStorage.decode(data, widgetSchemas: schemas)

        #expect(
            settings(loaded) == [
                [["showSeconds": "false", "timeZone": "Europe/Oslo"], ["showPercentage": "maybe"]],
                [["timeZone": "", "color": "teal"]],
            ])
    }

    @Test func decodeWithoutSchemasChangesNothing() throws {
        let original = document()
        let loaded = try DockStorage.decode(DockStorage.encode(original))
        #expect(settings(loaded) == settings(original))
    }

    @Test func sanitizeCountsChangedValues() {
        var doc = document()
        #expect(doc.sanitizeWidgetSettings(using: schemas) == 2)
        #expect(doc.sanitizeWidgetSettings(using: schemas) == 0)
        #expect(doc.sanitizeWidgetSettings(using: [:]) == 0)
    }

    @Test func legacyFileIsMigratedBeforeValidation() throws {
        // A v1 file names the clock by its old ID; the schema is keyed by the new one, so
        // validation only finds the widget if migration runs first.
        let legacy = #"""
            {
              "activeProfileID" : "6F0C9E4B-2B57-4C1F-9C55-3C7A8E1D0A01",
              "profiles" : [
                {
                  "id" : "6F0C9E4B-2B57-4C1F-9C55-3C7A8E1D0A01",
                  "items" : [
                    {
                      "id" : "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A02",
                      "kind" : { "widget" : { "_0" : { "settings" : { "showSeconds" : "1", "style" : "analog" }, "typeID" : "org.opendock.widget.clock" } } }
                    }
                  ],
                  "name" : "Default"
                }
              ],
              "settings" : { },
              "version" : 1
            }
            """#
        let loaded = try DockStorage.decode(Data(legacy.utf8), widgetSchemas: schemas)
        let clock = try #require(loaded.activeProfile.items.first?.widgetInstance)
        #expect(clock.typeID == BuiltInWidgetID.clock)
        #expect(clock.settings == ["showSeconds": "false", "style": "analog"])
    }

    @Test @MainActor func storeLoadsAndImportsThroughItsSchemas() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSettingsLoadTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = DockStorage(fileURL: dir.appendingPathComponent("dock.json"), widgetSchemas: schemas)
        try storage.save(document())

        let store = DockStore.load(from: storage)
        #expect(store.items.first?.widgetInstance?.settings == ["showSeconds": "false", "timeZone": "Europe/Oslo"])

        var tweaked = document()
        tweaked.updateWidgets { $0.settings["showSeconds"] = "nope" }
        try store.importData(DockStorage.encode(tweaked))
        #expect(store.items.first?.widgetInstance?.settings["showSeconds"] == "false")
    }
}
