import AppKit
import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// The tile's shortcut with a Run button, the shortcuts run from this tile lately, and every
/// other shortcut on the Mac. Clicking a row runs it; its menu puts it in the tile or opens
/// it in the Shortcuts editor.
struct ShortcutsPopoutView: View {
    let instance: WidgetInstance

    @Environment(\.widgetUpdateSettings) private var updater
    @State private var service = ShortcutsService.shared
    @State private var query = ""

    private var settings: ShortcutsSettings { ShortcutsSettings(instance: instance) }
    private var pinned: String? { settings.shortcutName }

    /// Shortcuts run from this tile, newest first, without the pinned one (it's in the header).
    private var recents: [String] { settings.recents.filter { $0 != pinned } }

    private var filtered: [String] { ShortcutsCatalog.filter(service.shortcuts, matching: query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !service.isAvailable {
                Text("The shortcuts command-line tool isn't on this Mac, so OpenDock can't run shortcuts.")
                    .foregroundStyle(.secondary)
            } else {
                if !recents.isEmpty {
                    section("Recent", names: recents)
                }
                allShortcuts
            }

            Divider()

            HStack {
                Button("Open Shortcuts") { Self.openShortcutsApp() }
                Spacer()
                Button {
                    Task { await service.refresh(force: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("Read the list of shortcuts again")
                .disabled(service.isRefreshing)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .task { await service.refresh(force: true) }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 12) {
            ShortcutIconView(
                symbol: ShortcutSymbolResolver.symbol(for: settings.symbol),
                tint: settings.tint,
                size: 40,
                state: pinned.flatMap { service.state(of: $0) })
            VStack(alignment: .leading, spacing: 2) {
                Text(pinned ?? "Shortcuts")
                    .font(.headline)
                    .lineLimit(1)
                Text(headerStatus)
                    .font(.caption)
                    .foregroundStyle(headerStatusColor)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if let pinned {
                Button("Run") { run(pinned) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(service.state(of: pinned)?.isRunning == true)
            }
        }
    }

    private var headerStatus: String {
        guard let pinned else { return "Pick a shortcut below, or in Settings › Dock Items." }
        if let state = service.state(of: pinned) {
            switch state {
            case .running: return "Running…"
            case let .succeeded(at): return "Ran at \(at.formatted(date: .omitted, time: .shortened))"
            case let .failed(failure, at):
                return "\(failure.message) · \(at.formatted(date: .omitted, time: .shortened))"
            }
        }
        if service.exists(pinned) == false { return "Not found in Shortcuts. Was it renamed?" }
        return "Click the tile, or Run, to run it."
    }

    private var headerStatusColor: Color {
        guard let pinned else { return .secondary }
        if service.state(of: pinned)?.failure != nil
            || (service.state(of: pinned) == nil && service.exists(pinned) == false)
        {
            return .red
        }
        return .secondary
    }

    // MARK: Lists

    @ViewBuilder
    private var allShortcuts: some View {
        if !service.hasLoaded {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading your shortcuts…").foregroundStyle(.secondary)
            }
        } else if service.shortcuts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No shortcuts yet.").foregroundStyle(.secondary)
                Button("Create One in Shortcuts") {
                    if let url = ShortcutsURL.create { NSWorkspace.shared.open(url) }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("All Shortcuts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(service.shortcuts.count))
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                if service.shortcuts.count > 8 {
                    TextField("Filter", text: $query, prompt: Text("Filter shortcuts"))
                        .textFieldStyle(.roundedBorder)
                }
                if filtered.isEmpty {
                    WidgetCaption("No shortcut matches “\(query)”.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(filtered, id: \.self) { name in
                                row(name)
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func section(_ title: String, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(names, id: \.self) { name in
                    row(name)
                }
            }
        }
    }

    /// One shortcut: click to run, with its state beside the name and a menu for the rest.
    private func row(_ name: String) -> some View {
        let state = service.state(of: name)
        let missing = service.exists(name) == false
        return HStack(spacing: 8) {
            Button {
                run(name)
            } label: {
                HStack(spacing: 8) {
                    Group {
                        if state?.isRunning == true {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: rowSymbol(state: state, missing: missing))
                                .foregroundStyle(rowSymbolColor(state: state, missing: missing))
                        }
                    }
                    .frame(width: 16)
                    Text(name)
                        .lineLimit(1)
                        .foregroundStyle(missing ? .secondary : .primary)
                    Spacer(minLength: 0)
                    if name == pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .help("In the tile")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state?.isRunning == true)
            .help(missing ? "\(name) isn't in Shortcuts any more" : "Run \(name)")
            .accessibilityLabel(name)
            .accessibilityHint("Runs the shortcut")

            Menu {
                Button("Run") { run(name) }
                if name != pinned {
                    Button("Use in Tile") { pin(name) }
                }
                Button("Edit in Shortcuts…") {
                    if let url = ShortcutsURL.open(name: name) { NSWorkspace.shared.open(url) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More for \(name)")
        }
        .padding(.vertical, 2)
    }

    private func rowSymbol(state: ShortcutRunState?, missing: Bool) -> String {
        if missing { return "questionmark.circle" }
        switch state {
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .running, nil: return "play.circle"
        }
    }

    private func rowSymbolColor(state: ShortcutRunState?, missing: Bool) -> Color {
        if missing { return .secondary }
        switch state {
        case .succeeded: return .green
        case .failed: return .red
        case .running, nil: return .secondary
        }
    }

    // MARK: Actions

    private func run(_ name: String) {
        updater(settings.recording(name))
        Task { await service.run(name) }
    }

    private func pin(_ name: String) {
        updater.set(ShortcutsSettings.shortcut.name, to: name, in: instance)
    }

    static func openShortcutsApp() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Shortcuts.app"),
            configuration: NSWorkspace.OpenConfiguration())
    }
}
