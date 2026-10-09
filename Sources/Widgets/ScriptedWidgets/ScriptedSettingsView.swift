import DockCore
import DockWidgetKit
import ScriptedWidgetRuntime
import SwiftUI

/// Settings for one scripted tile: which installed widget it runs, buttons to reload the
/// Widgets folder and show it in Finder, then one control per setting the widget's manifest
/// declares, built from the schema the way the built-in widgets' views are written by hand.
/// Errors from the script, and folders that didn't load, are shown here too.
struct ScriptedSettingsView: View {
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var instance: WidgetInstance
    @State private var library = ScriptedWidgetLibrary.shared

    init(instance: WidgetInstance) {
        _instance = State(initialValue: instance)
    }

    private var settings: ScriptedWidgetSettings { ScriptedWidgetSettings(instance: instance) }
    private var package: ScriptedWidgetPackage? { settings.packageID.flatMap(library.package(for:)) }

    var body: some View {
        Form {
            Picker("Widget", selection: packageBinding) {
                Text("None").tag("")
                if !library.packages.isEmpty {
                    Divider()
                    ForEach(library.packages) { package in
                        Text(package.manifest.name).tag(package.id)
                    }
                }
                if let id = settings.packageID, library.package(for: id) == nil {
                    Text("\(id) (not installed)").tag(id)
                }
            }

            HStack {
                Button("Reload") { library.reload() }
                Button("Show Widgets Folder") { library.revealInFinder() }
            }
            if library.hasLoaded, library.packages.isEmpty {
                WidgetCaption(
                    "No scripted widgets are installed. Put a widget's folder, with its manifest.json and main.js, in the Widgets folder; the hello sample in OpenDock's Examples folder is a start."
                )
            }

            if let package {
                about(package)
                if let error = library.errors[package.id] {
                    Label(error.description, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
                ForEach(package.manifest.settings) { definition in
                    control(for: definition)
                    WidgetCaption(definition.key.summary)
                }
            }

            if !library.problems.isEmpty {
                problems
            }
        }
        .task { library.loadIfNeeded() }
    }

    /// Name, version, author, and what the widget may do.
    private func about(_ package: ScriptedWidgetPackage) -> some View {
        let manifest = package.manifest
        var line = "\(manifest.name) \(manifest.version)"
        if let author = manifest.author, !author.isEmpty { line += " · \(author)" }
        return VStack(alignment: .leading, spacing: 2) {
            WidgetCaption(line)
            WidgetCaption(manifest.summary)
            ForEach(manifest.permissions.summary, id: \.self) { permission in
                WidgetCaption(permission)
            }
        }
    }

    /// Folders in the Widgets directory that look like widgets but didn't load, and why.
    private var problems: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Problems")
                .font(.caption.weight(.semibold))
            ForEach(library.problems) { problem in
                Label("\(problem.folderName): \(problem.message)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
    }

    /// The control for one manifest setting, by its type.
    @ViewBuilder
    private func control(for definition: ScriptedSettingDefinition) -> some View {
        let key = definition.key
        let title = LocalizedStringKey(definition.title)
        switch key.type {
        case .bool:
            Toggle(title, isOn: updater.boolBinding(key, in: $instance))
        case let .choice(choices):
            Picker(title, selection: updater.stringBinding(key, in: $instance)) {
                ForEach(choices, id: \.self) { choice in
                    Text(choice).tag(choice)
                }
            }
        case let .integer(range):
            Stepper(value: updater.intBinding(key, in: $instance), in: range) {
                LabeledContent(title) {
                    Text(String(key.intValue(in: instance.settings)))
                        .monospacedDigit()
                }
            }
        case .number:
            WidgetTextSetting(title, key: key, instance: $instance, prompt: Text(key.defaultValue))
        case .text:
            WidgetTextSetting(title, key: key, instance: $instance)
        case .timeZone:
            WidgetTextSetting(title, key: key, instance: $instance, prompt: Text("Europe/Oslo"))
        }
    }

    private var packageBinding: Binding<String> {
        Binding(
            get: { settings.packageID ?? "" },
            set: { newValue in
                instance.settings[ScriptedWidgetSettings.package.name] = newValue
                updater(instance)
            }
        )
    }
}
