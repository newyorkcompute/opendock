import DockCore
import Foundation
import ScriptedWidgetRuntime
import Testing

@Suite("Scripted widget manifest")
struct ManifestTests {
    private func decode(_ json: String) throws(ScriptedWidgetError) -> ScriptedWidgetManifest {
        try ScriptedWidgetManifest.decode(Data(json.utf8))
    }

    /// The error a manifest fails with, or nil when it loads.
    private func failure(_ json: String) -> ScriptedManifestError? {
        do {
            _ = try decode(json)
            return nil
        } catch {
            if case let .manifest(reason) = error { return reason }
            Issue.record("unexpected error \(error)")
            return nil
        }
    }

    private func isMalformed(_ error: ScriptedManifestError?) -> Bool {
        if case .malformed = error { return true }
        return false
    }

    private func manifest(settings: String = "[]", permissions: String = "{}", extra: String = "") -> String {
        """
        {
          "apiVersion": 1, "id": "com.example.test", "name": "Test", "version": "1.0", "summary": "A test.",
          "settings": \(settings), "permissions": \(permissions)\(extra)
        }
        """
    }

    @Test func decodesTheHelloSample() throws {
        let manifest = try ScriptedWidgetManifest.decode(Data(contentsOf: SampleWidget.manifestURL))
        #expect(manifest.id == "com.example.hello")
        #expect(manifest.name == "Hello")
        #expect(manifest.apiVersion == 1)
        #expect(manifest.symbol == "hand.wave")
        #expect(manifest.main == "main.js")
        #expect(manifest.permissions.isEmpty)
        #expect(manifest.settings.map(\.key.name) == ["name", "showRing", "color", "refreshSeconds"])
        #expect(manifest.settings.map(\.title) == ["Name", "Show seconds ring", "Ring color", "Redraw every"])
        #expect(manifest.settingsSchema.key(named: "refreshSeconds")?.type == .integer(1 ... 3600))
        #expect(
            manifest.settingsSchema.defaults == [
                "name": "World", "showRing": "true", "color": "teal", "refreshSeconds": "1",
            ])
    }

    @Test func fillsInDefaultsForOptionalFields() throws {
        let manifest = try decode(manifest())
        #expect(manifest.symbol == "curlybraces")
        #expect(manifest.main == "main.js")
        #expect(manifest.author == nil)
        #expect(manifest.settings.isEmpty)
        #expect(manifest.permissions == .none)
    }

    @Test func ignoresUnknownKeys() throws {
        let manifest = try decode(manifest(extra: ", \"minimumOpenDockVersion\": \"9.9\", \"icon\": {\"x\": 1}"))
        #expect(manifest.id == "com.example.test")
    }

    @Test func decodesEverySettingType() throws {
        let manifest = try decode(
            manifest(
                settings: """
                    [
                      {"key": "a", "type": "bool", "default": false, "summary": "A."},
                      {"key": "b", "type": "text", "default": "hi", "summary": "B."},
                      {"key": "c", "type": "choice", "choices": ["x", "y"], "default": "y", "summary": "C."},
                      {"key": "d", "type": "integer", "min": 0, "max": 10, "default": 3, "summary": "D."},
                      {"key": "e", "type": "number", "min": -1.5, "max": 1.5, "default": 0.25, "summary": "E."},
                      {"key": "f", "type": "timeZone", "default": "", "summary": "F."}
                    ]
                    """))
        let types = manifest.settings.map(\.key.type)
        #expect(
            types == [.bool, .text, .choice(["x", "y"]), .integer(0 ... 10), .number(-1.5 ... 1.5), .timeZone])
        #expect(manifest.settings.map(\.key.defaultValue) == ["false", "hi", "y", "3", "0.25", ""])
    }

    @Test func settingsWithoutATitleGetOneFromTheKey() throws {
        let manifest = try decode(
            manifest(settings: #"[{"key": "refreshSeconds", "type": "text", "default": "", "summary": "S."}]"#))
        #expect(manifest.settings.first?.title == "Refresh seconds")
        #expect(ScriptedWidgetManifest.defaultTitle(forKey: "name") == "Name")
        #expect(ScriptedWidgetManifest.defaultTitle(forKey: "showCPUHistory") == "Show c p u history")
    }

    @Test func settingsReadThroughTheSchemaAndAreTyped() throws {
        let manifest = try ScriptedWidgetManifest.decode(Data(contentsOf: SampleWidget.manifestURL))
        let values = manifest.scriptSettings(from: [
            "name": "Oslo", "showRing": "maybe", "refreshSeconds": "30", "color": "teal", "package": "x",
        ])
        #expect(
            values == [
                "name": .string("Oslo"), "showRing": .bool(true), "color": .string("teal"),
                "refreshSeconds": .number(30),
            ])
        #expect(manifest.scriptSettings(from: [:])["showRing"] == .bool(true))
        #expect(manifest.scriptSettings(from: ["refreshSeconds": "0"])["refreshSeconds"] == .number(1))
    }

    @Test func permissionsDecodeInBothShapes() throws {
        let permissions = try decode(
            manifest(permissions: #"{"network": ["api.github.com"], "openURL": true, "shortcuts": ["Lights"]}"#)
        ).permissions
        #expect(permissions.networkHosts == ["api.github.com"])
        #expect(permissions.openURL)
        #expect(permissions.shortcuts == ["Lights"])
        #expect(permissions.summary.count == 3)
        #expect(try decode(manifest(permissions: #"{"shortcuts": true}"#)).permissions.shortcuts == [])
        #expect(try decode(manifest(permissions: #"{"shortcuts": false}"#)).permissions.shortcuts == nil)
    }

    @Test func refusesWhatItCannotRun() {
        #expect(isMalformed(failure("not json")))
        #expect(isMalformed(failure(#"{"apiVersion": "one"}"#)))
        #expect(failure("{}") == .missingField("apiVersion"))
        #expect(
            failure(#"{"apiVersion": 2, "id": "a.b", "name": "n", "version": "1", "summary": "s"}"#)
                == .unsupportedAPIVersion(2))
        #expect(
            failure(manifest().replacingOccurrences(of: "com.example.test", with: "nodots")) == .invalidID("nodots"))
        #expect(failure(manifest().replacingOccurrences(of: "com.example.test", with: "a..b")) == .invalidID("a..b"))
        #expect(failure(manifest().replacingOccurrences(of: "com.example.test", with: "a b.c")) == .invalidID("a b.c"))
        #expect(
            failure(
                manifest().replacingOccurrences(of: "com.example.test", with: "com.newyorkcompute.opendock.widget.x"))
                == .reservedID("com.newyorkcompute.opendock.widget.x"))
        #expect(
            failure(manifest().replacingOccurrences(of: "\"name\": \"Test\"", with: "\"name\": \"  \""))
                == .missingField("name"))
        #expect(failure(manifest(extra: ", \"main\": \"../other.js\"")) == .invalidMainPath("../other.js"))
        #expect(failure(manifest(extra: ", \"main\": \"/etc/passwd\"")) == .invalidMainPath("/etc/passwd"))
        #expect(failure(manifest(permissions: #"{"clipboard": true}"#)) == .unknownPermission("clipboard"))
        #expect(failure(manifest(permissions: #"{"network": true}"#)) == .invalidPermission("network"))
    }

    @Test func refusesBadSettings() {
        func setting(_ body: String) -> String { manifest(settings: "[\(body)]") }
        #expect(
            failure(setting(#"{"key": "Name", "type": "text", "default": "", "summary": "S."}"#))
                == .invalidSettingKey("Name"))
        #expect(
            failure(setting(#"{"key": "my_key", "type": "text", "default": "", "summary": "S."}"#))
                == .invalidSettingKey("my_key"))
        #expect(
            failure(setting(#"{"key": "package", "type": "text", "default": "", "summary": "S."}"#))
                == .reservedSettingKey("package"))
        #expect(
            failure(
                setting(
                    #"{"key": "a", "type": "bool", "default": true, "summary": "A."}, {"key": "a", "type": "bool", "default": true, "summary": "A."}"#
                )) == .duplicateSettingKey("a"))
        #expect(
            failure(setting(#"{"key": "a", "type": "color", "default": "", "summary": "A."}"#))
                == .invalidSettingType(key: "a", type: "color"))
        #expect(
            failure(setting(#"{"key": "a", "type": "integer", "min": 5, "max": 1, "default": 1, "summary": "A."}"#))
                == .invalidSettingRange(key: "a"))
        #expect(
            failure(setting(#"{"key": "a", "type": "integer", "min": 0.5, "max": 1, "default": 1, "summary": "A."}"#))
                == .invalidSettingRange(key: "a"))
        #expect(
            failure(setting(#"{"key": "a", "type": "number", "min": 0, "default": 1, "summary": "A."}"#))
                == .invalidSettingRange(key: "a"))
        #expect(
            failure(setting(#"{"key": "a", "type": "choice", "default": "x", "summary": "A."}"#))
                == .emptyChoices(key: "a"))
        #expect(
            failure(setting(#"{"key": "a", "type": "bool", "default": "yes", "summary": "A."}"#))
                == .invalidDefault(key: "a", value: "yes"))
        #expect(
            failure(setting(#"{"key": "a", "type": "integer", "min": 1, "max": 3, "default": 7, "summary": "A."}"#))
                == .invalidDefault(key: "a", value: "7"))
        #expect(
            failure(setting(#"{"key": "a", "type": "bool", "default": "", "summary": "A."}"#))
                == .invalidDefault(key: "a", value: ""))
        #expect(
            failure(setting(#"{"key": "a", "type": "number", "min": 0, "max": 1, "default": "", "summary": "A."}"#))
                == nil)
        #expect(
            failure(setting(#"{"key": "a", "type": "choice", "choices": ["x"], "default": "", "summary": "A."}"#))
                == nil)
        #expect(failure(setting(#"{"key": "a", "type": "bool", "default": true}"#)) == .missingSummary(key: "a"))
    }

    @Test func errorsReadAsSentences() {
        for error in [
            ScriptedManifestError.unsupportedAPIVersion(3), .invalidID("x"), .reservedSettingKey("package"),
            .invalidSettingRange(key: "a"), .unknownPermission("clipboard"), .malformed("missing \"id\""),
        ] {
            #expect(error.description.hasSuffix("."), "\(error)")
        }
        #expect(ScriptedManifestError.unsupportedAPIVersion(3).description.contains("Update OpenDock"))
        #expect(
            ScriptedWidgetError.manifest(.missingField("id")).description
                == "manifest.json: \"id\" is missing or empty.")
    }

    @Test func idRules() {
        #expect(ScriptedWidgetManifest.isValidID("com.example.hello"))
        #expect(ScriptedWidgetManifest.isValidID("io.github.alice.github-stars_v2"))
        #expect(!ScriptedWidgetManifest.isValidID("hello"))
        #expect(!ScriptedWidgetManifest.isValidID(".hello"))
        #expect(!ScriptedWidgetManifest.isValidID("hello."))
        #expect(!ScriptedWidgetManifest.isValidID("a.b/c"))
        #expect(!ScriptedWidgetManifest.isValidID("ü.b"))
        #expect(!ScriptedWidgetManifest.isValidID(String(repeating: "a", count: 100) + ".b"))
    }
}
