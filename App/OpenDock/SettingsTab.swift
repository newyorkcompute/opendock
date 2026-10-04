import SwiftUI

/// The panes of the Settings window, in toolbar order.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case dockItems
    case widgets
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .dockItems: "Dock Items"
        case .widgets: "Widgets"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .dockItems: "dock.rectangle"
        case .widgets: "square.grid.2x2"
        case .about: "info.circle"
        }
    }

    /// Fixed content size. Settings windows aren't user-resizable; each pane picks a
    /// height that fits its content and scrolls beyond that.
    var contentSize: CGSize {
        let width: CGFloat = 520
        return switch self {
        case .general: CGSize(width: width, height: 640)
        case .dockItems: CGSize(width: width, height: 560)
        case .widgets: CGSize(width: width, height: 380)
        case .about: CGSize(width: width, height: 360)
        }
    }

    @ViewBuilder
    var content: some View {
        switch self {
        case .general: GeneralSettingsTab()
        case .dockItems: DockItemsTab()
        case .widgets: WidgetsTab()
        case .about: AboutTab()
        }
    }
}
