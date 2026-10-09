import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// Settings for one Shortcuts tile: which shortcut, its icon and color, and whether to show
/// its name.
struct ShortcutsSettingsView: View {
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var instance: WidgetInstance
    @State private var service = ShortcutsService.shared
    @State private var customSymbol: String

    init(instance: WidgetInstance) {
        _instance = State(initialValue: instance)
        let symbol = ShortcutsSettings.symbol.value(in: instance.settings)
        _customSymbol = State(initialValue: ShortcutSymbols.suggested.contains(symbol) ? "" : symbol)
    }

    private var settings: ShortcutsSettings { ShortcutsSettings(instance: instance) }

    /// The picker's choices: every shortcut on the Mac, plus the stored one if it's gone, so
    /// the picker can still show what the tile is set to.
    private var choices: [String] {
        guard let name = settings.shortcutName, service.hasLoaded, !service.shortcuts.contains(name) else {
            return service.shortcuts
        }
        return service.shortcuts + [name]
    }

    var body: some View {
        Form {
            Picker("Shortcut", selection: shortcutBinding) {
                Text("None").tag("")
                if !choices.isEmpty {
                    Divider()
                    ForEach(choices, id: \.self) { name in
                        if service.exists(name) == false {
                            Text("\(name) (not found)").tag(name)
                        } else {
                            Text(name).tag(name)
                        }
                    }
                }
            }
            availability

            Toggle("Show name", isOn: updater.boolBinding(ShortcutsSettings.showName, in: $instance))

            Picker("Color", selection: tintBinding) {
                ForEach(ShortcutTint.allCases, id: \.self) { tint in
                    Label {
                        Text(tint.displayName)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(tint.color)
                            .imageScale(.small)
                    }
                    .tag(tint)
                }
            }

            LabeledContent("Icon") {
                VStack(alignment: .leading, spacing: 8) {
                    symbolGrid
                    TextField("Other SF Symbol", text: $customSymbol, prompt: Text("Any SF Symbol name"))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customSymbol) { _, newValue in
                            // Applied as soon as it names a symbol this Mac has; clearing the
                            // field leaves the icon alone, since the grid is there to pick one.
                            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty, ShortcutSymbolResolver.symbol(for: trimmed) == trimmed {
                                setSymbol(trimmed)
                            }
                        }
                }
            }
        }
        .task { await service.refresh() }
    }

    @ViewBuilder
    private var availability: some View {
        if !service.isAvailable {
            Text("The shortcuts command-line tool isn't on this Mac, so the tile can't run anything.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if service.hasLoaded, service.shortcuts.isEmpty {
            Text("No shortcuts found. Create one in the Shortcuts app, then come back here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The quick picks, with the current one outlined.
    private var symbolGrid: some View {
        let current = ShortcutSymbolResolver.symbol(for: settings.symbol)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 28, maximum: 32), spacing: 4)], spacing: 4) {
            ForEach(ShortcutSymbols.suggested, id: \.self) { symbol in
                Button {
                    customSymbol = ""
                    setSymbol(symbol)
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(symbol == current ? settings.tint.color.opacity(0.25) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(symbol == current ? settings.tint.color : Color.clear, lineWidth: 1.5)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(symbol)
                .accessibilityLabel(symbol)
                .accessibilityAddTraits(symbol == current ? .isSelected : [])
            }
        }
    }

    // MARK: Bindings

    private var shortcutBinding: Binding<String> {
        Binding(
            get: { settings.shortcutName ?? "" },
            set: { newValue in
                instance.settings[ShortcutsSettings.shortcut.name] = newValue
                updater(instance)
            }
        )
    }

    private var tintBinding: Binding<ShortcutTint> {
        Binding(
            get: { settings.tint },
            set: { newValue in
                instance.settings[ShortcutsSettings.color.name] = newValue.rawValue
                updater(instance)
            }
        )
    }

    private func setSymbol(_ symbol: String) {
        guard symbol != settings.symbol else { return }
        instance.settings[ShortcutsSettings.symbol.name] = symbol
        updater(instance)
    }
}
