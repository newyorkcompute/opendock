import AppKit
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
    @State private var pendingInstall: ScriptedInstallInspection?
    @State private var confirmRemove = false

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
                Button("Add Scripted Widget…") { addWidget() }
                Button("Reload") { library.reload() }
            }
            HStack {
                Button("Reveal in Finder") { library.reveal(package) }
                if package != nil {
                    Button("Remove") { confirmRemove = true }
                }
            }
            if library.hasLoaded, library.packages.isEmpty {
                WidgetCaption(
                    "No scripted widgets are installed. Add one above, or put its folder in the Widgets folder."
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
            if !library.errorLog.entries.isEmpty {
                errorLog
            }
        }
        .task { library.loadIfNeeded() }
        .sheet(item: $pendingInstall) { inspection in
            InstallConfirmation(inspection: inspection) {
                pendingInstall = nil
            } confirm: {
                if let id = library.install(from: inspection.source) {
                    instance.settings[ScriptedWidgetSettings.package.name] = id
                    updater(instance)
                }
                pendingInstall = nil
            }
        }
        .confirmationDialog(
            "Remove \(package?.manifest.name ?? "this widget")?",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let package { library.remove(package) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the widget and its saved data. Tiles that used it show it isn't installed.")
        }
    }

    /// Folder or zip. A valid package is confirmed, with its permissions, before anything is copied.
    private func addWidget() {
        let panel = NSOpenPanel()
        panel.title = "Add Scripted Widget"
        panel.message = "Choose a widget folder, or a .zip of one."
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingInstall = library.inspect(url: url)
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

    /// Install and script failures, oldest first.
    private var errorLog: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Error log")
                .font(.caption.weight(.semibold))
            ForEach(library.errorLog.entries) { entry in
                Text(entry.message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
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

/// The sheet shown after a folder or zip validates: the widget's name and the permissions it
/// asked for, before it is copied in.
private struct InstallConfirmation: View {
    var inspection: ScriptedInstallInspection
    var cancel: () -> Void
    var confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add \(inspection.manifest.name)?")
                .font(.headline)
            Text("\(inspection.manifest.name) \(inspection.manifest.version)")
                .font(.caption)
            Text(inspection.manifest.summary)
                .font(.caption)
            if inspection.manifest.permissions.summary.isEmpty {
                Text("It doesn't ask to contact the network, open links, or run shortcuts.")
                    .font(.caption)
            } else {
                ForEach(inspection.manifest.permissions.summary, id: \.self) { line in
                    Text(line).font(.caption)
                }
            }
            if inspection.replacesExisting {
                Text("This replaces the installed copy. Saved data next to the widget is kept.")
                    .font(.caption)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                Button("Add", action: confirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
    }
}
