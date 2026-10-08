import BuiltInWidgets
import DockCore
import DockWidgetKit
import Testing

@MainActor
@Suite("Built-in widget schemas")
struct WidgetSchemaTests {
    /// These are stored in users' `dock.json` files. If this test fails, don't update the
    /// strings here: put the old ID back, or add a `DockStorage` migration.
    @Test func typeIDsNeverChange() {
        let pinned = [
            "com.newyorkcompute.opendock.widget.clock",
            "com.newyorkcompute.opendock.widget.battery",
            "com.newyorkcompute.opendock.widget.calendar",
            "com.newyorkcompute.opendock.widget.systemactivity",
            "com.newyorkcompute.opendock.widget.weather",
            "com.newyorkcompute.opendock.widget.nowplaying",
        ]
        #expect(BuiltInWidgets.all.map { $0.typeID } == pinned)
        #expect(
            [
                BuiltInWidgetID.clock, BuiltInWidgetID.battery, BuiltInWidgetID.calendar,
                BuiltInWidgetID.systemActivity, BuiltInWidgetID.weather, BuiltInWidgetID.nowPlaying,
            ] == pinned)
    }

    @Test func keyNamesAreUniqueAndCamelCase() {
        for widget in BuiltInWidgets.all {
            let names = widget.settingsSchema.keys.map(\.name)
            #expect(Set(names).count == names.count, "\(widget.displayName) declares a key twice")
            for name in names {
                #expect(
                    name.first?.isLowercase == true && name.allSatisfy { $0.isLetter || $0.isNumber },
                    "\(widget.displayName).\(name) should be a lowerCamelCase identifier")
            }
        }
    }

    @Test func defaultsAreValidForTheirKeys() {
        for widget in BuiltInWidgets.all {
            for key in widget.settingsSchema.keys {
                #expect(key.isValid(key.defaultValue), "\(widget.displayName).\(key.name) default is invalid")
                #expect(!key.summary.isEmpty, "\(widget.displayName).\(key.name) has no description")
                #expect(
                    key.summary.hasSuffix("."), "\(widget.displayName).\(key.name) description should be a sentence")
            }
        }
    }

    @Test func newInstancesStartFromTheSchema() {
        for widget in BuiltInWidgets.all {
            let schema = widget.settingsSchema
            #expect(widget.defaultSettings == schema.defaults)
            let instance = widget.makeInstance()
            #expect(instance.typeID == widget.typeID)
            #expect(schema.invalidKeys(in: instance.settings).isEmpty)
            #expect(schema.sanitized(instance.settings) == instance.settings)
        }
    }

    @Test func registryExposesSchemas() {
        let registry = WidgetRegistry()
        registry.register(BuiltInWidgets.all)
        #expect(registry.settingsSchemas == BuiltInWidgets.settingsSchemas)
        #expect(registry.descriptors.map(\.settingsSchema) == BuiltInWidgets.all.map { $0.settingsSchema })
        #expect(registry.settingsSchemas[BuiltInWidgetID.clock]?.key(named: "timeZone")?.type == .timeZone)
    }

    @Test func sanitizingKeepsUnknownKeysAndFixesBadValues() {
        let clock = BuiltInWidgets.settingsSchemas[BuiltInWidgetID.clock]
        let cleaned = clock?.sanitized([
            "showSeconds": "sometimes",
            "showDate": "false",
            "timeZone": "Atlantis/Lost",
            "label": "  Oslo ",
            "theme": "from a newer build",
        ])
        #expect(
            cleaned == [
                "showSeconds": "false",
                "showDate": "false",
                "timeZone": "",
                "label": "  Oslo ",
                "theme": "from a newer build",
            ])
    }

    @Test func weatherLocationIsValidatedByCoordinate() {
        let weather = BuiltInWidgets.settingsSchemas[BuiltInWidgetID.weather]
        let cleaned = weather?.sanitized([
            "unit": "kelvin",
            "locationMode": "place",
            "placeName": "Oslo",
            "latitude": "59.91",
            "longitude": "200",
        ])
        #expect(
            cleaned == [
                "unit": "",
                "locationMode": "place",
                "placeName": "Oslo",
                "latitude": "59.91",
                "longitude": "",
            ])
        #expect(weather?.key(named: "unit")?.isValid("fahrenheit") == true)
        #expect(weather?.key(named: "latitude")?.isValid("") == true)
    }
}
