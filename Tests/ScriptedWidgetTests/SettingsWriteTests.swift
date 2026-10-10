import Foundation
import ScriptedWidgetRuntime
import Testing

@Suite("Scripted settings writes")
struct SettingsWriteTests {
    private var manifest: ScriptedWidgetManifest {
        get throws {
            try ScriptedWidgetManifest.decode(
                Data(
                    SampleWidget.manifest(
                        settings: """
                            [
                              {"key": "name", "type": "text", "default": "World", "summary": "Who."},
                              {"key": "flag", "type": "bool", "default": true, "summary": "F."},
                              {"key": "count", "type": "integer", "min": 0, "max": 9, "default": 1, "summary": "C."},
                              {"key": "ratio", "type": "number", "min": 0, "max": 1, "default": 0.5, "summary": "R."},
                              {"key": "color", "type": "choice", "choices": ["teal", "blue"],
                               "default": "teal", "summary": "Color."}
                            ]
                            """
                    ).utf8))
        }
    }

    @Test func storesAValueTheSchemaAccepts() throws {
        let manifest = try manifest
        #expect(try ScriptedSettingsWrite.storedString(.string("Oslo"), for: "name", in: manifest) == "Oslo")
        #expect(try ScriptedSettingsWrite.storedString(.bool(false), for: "flag", in: manifest) == "false")
        #expect(try ScriptedSettingsWrite.storedString(.number(4), for: "count", in: manifest) == "4")
        #expect(try ScriptedSettingsWrite.storedString(.number(0.25), for: "ratio", in: manifest) == "0.25")
        #expect(try ScriptedSettingsWrite.storedString(.string("blue"), for: "color", in: manifest) == "blue")
    }

    @Test func rejectsTheWrongTypeAnUnknownKeyAndAValueOutsideTheSchema() throws {
        let manifest = try manifest
        let missing = ScriptedWidgetError.invalidSetting(key: "nope", detail: "there is no setting named \"nope\".")
        #expect(throws: missing) {
            try ScriptedSettingsWrite.storedString(.string("x"), for: "nope", in: manifest)
        }
        #expect(throws: ScriptedWidgetError.self) {
            try ScriptedSettingsWrite.storedString(.string("true"), for: "flag", in: manifest)
        }
        #expect(throws: ScriptedWidgetError.self) {
            try ScriptedSettingsWrite.storedString(.number(1.5), for: "count", in: manifest)
        }
        #expect(throws: ScriptedWidgetError.self) {
            try ScriptedSettingsWrite.storedString(.number(12), for: "count", in: manifest)
        }
        #expect(throws: ScriptedWidgetError.self) {
            try ScriptedSettingsWrite.storedString(.string("red"), for: "color", in: manifest)
        }
    }
}
