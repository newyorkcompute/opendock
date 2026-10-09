import DockCore
import SwiftUI

/// Maps widget type IDs to implementations. The app registers the built-in
/// widgets at launch; the shell looks them up when rendering.
@Observable
public final class WidgetRegistry {
    public private(set) var widgets: [any DockWidget.Type] = []

    public init() {}

    public func register(_ widget: any DockWidget.Type) {
        guard !widgets.contains(where: { $0.typeID == widget.typeID }) else { return }
        widgets.append(widget)
    }

    public func register(_ list: [any DockWidget.Type]) {
        list.forEach(register)
    }

    /// Identifiable summaries of every registered widget, for pickers and menus.
    public var descriptors: [WidgetDescriptor] {
        widgets.map(WidgetDescriptor.init)
    }

    /// Settings schemas of every registered widget, by type ID, for `DockStorage`.
    public var settingsSchemas: [String: WidgetSettingsSchema] {
        Self.settingsSchemas(of: widgets)
    }

    /// Settings schemas by type ID, for building a `DockStorage` before the registry exists.
    public static func settingsSchemas(of widgets: [any DockWidget.Type]) -> [String: WidgetSettingsSchema] {
        Dictionary(widgets.map { ($0.typeID, $0.settingsSchema) }, uniquingKeysWith: { first, _ in first })
    }

    public func widget(for typeID: String) -> (any DockWidget.Type)? {
        widgets.first { $0.typeID == typeID }
    }

    public func widget(for instance: WidgetInstance) -> (any DockWidget.Type)? {
        widget(for: instance.typeID)
    }

    /// Renders an instance, or a placeholder if its type is unknown
    /// (for example, a document exported from a newer build).
    public func view(for instance: WidgetInstance) -> AnyView {
        if let widget = widget(for: instance) {
            return widget.makeView(instance: instance)
        }
        return AnyView(UnknownWidgetView(typeID: instance.typeID))
    }

    public func popout(for instance: WidgetInstance) -> AnyView? {
        widget(for: instance)?.makePopout(instance: instance)
    }

    public func displayName(for instance: WidgetInstance) -> String {
        widget(for: instance)?.displayName ?? "Unknown widget"
    }

    /// Whether `instance`'s tile takes `drop` (see `DockWidget.acceptsDrop(_:instance:)`).
    public func acceptsDrop(_ drop: WidgetDrop, on instance: WidgetInstance) -> Bool {
        widget(for: instance)?.acceptsDrop(drop, instance: instance) ?? false
    }

    /// Hands `drop` to `instance`'s widget. Returns whether it was taken.
    public func performDrop(_ drop: WidgetDrop, on instance: WidgetInstance) -> Bool {
        widget(for: instance)?.performDrop(drop, instance: instance) ?? false
    }
}

/// Value-type summary of a widget type. `Identifiable` by `typeID` so it works
/// directly in `ForEach` and `Picker`.
public struct WidgetDescriptor: Identifiable, Hashable, Sendable {
    public var id: String { typeID }
    public let typeID: String
    public let displayName: String
    public let systemImage: String
    public let summary: String
    public let settingsSchema: WidgetSettingsSchema

    public init(_ widget: any DockWidget.Type) {
        typeID = widget.typeID
        displayName = widget.displayName
        systemImage = widget.systemImage
        summary = widget.summary
        settingsSchema = widget.settingsSchema
    }
}

/// Shown when a saved widget type isn't registered in this build.
struct UnknownWidgetView: View {
    let typeID: String

    var body: some View {
        WidgetTile {
            VStack(alignment: .leading, spacing: 2) {
                Label("Unavailable", systemImage: "questionmark.square.dashed")
                    .font(.caption.weight(.semibold))
                Text(typeID.split(separator: ".").last.map(String.init) ?? typeID)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
