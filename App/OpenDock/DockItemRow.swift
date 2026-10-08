import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// One row in the Dock Items list: icon, name, kind, and quick actions.
struct DockItemRow: View {
    let item: DockItem

    @Environment(WidgetRegistry.self) private var registry

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .lineLimit(1)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if isMissing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .help("This item no longer exists at its saved location.")
            }

            if let fileURL, !isMissing {
                Button {
                    AppLauncher.revealInFinder(fileURL)
                } label: {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var icon: some View {
        if let fileURL {
            Image(nsImage: AppIconProvider.shared.icon(for: fileURL))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: symbolName)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }

    private var fileURL: URL? {
        item.appItem?.url ?? item.folderItem?.url
    }

    private var isMissing: Bool {
        guard let fileURL else { return false }
        return !FileManager.default.fileExists(atPath: fileURL.path)
    }

    private var symbolName: String {
        switch item.kind {
        case .app, .folder: "questionmark.app.dashed"
        case .spacer: "rectangle.dashed"
        case .divider: "rectangle.split.2x1"
        case .trash: "trash"
        case let .widget(instance): registry.widget(for: instance)?.systemImage ?? "questionmark.square.dashed"
        }
    }

    private var name: String {
        switch item.kind {
        case let .app(app): app.displayName
        case let .folder(folder): folder.displayName
        case .spacer: "Spacer"
        case .divider: "Divider"
        case .trash: "Trash"
        case let .widget(instance): registry.displayName(for: instance)
        }
    }

    private var caption: String {
        switch item.kind {
        case let .app(app):
            isMissing ? "Missing: \(app.url.path)" : "Application"
        case let .folder(folder):
            isMissing
                ? "Missing: \(folder.url.path)" : folder.url.deletingLastPathComponent().abbreviatingWithTildeInPath
        case let .spacer(spacer):
            spacer.size == .small ? "Small spacer" : "Regular spacer"
        case .divider:
            "Separator line"
        case .trash:
            "The Trash, at the end of the dock"
        case let .widget(instance):
            registry.widget(for: instance) == nil ? "Widget not available in this build" : "Widget"
        }
    }
}

private extension URL {
    var abbreviatingWithTildeInPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
