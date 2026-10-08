import AppKit
import DockCore
import SwiftUI
import SystemServices

/// A folder's contents in a grid, shown in a popover over the folder's dock icon.
/// Clicking a file opens it; clicking a subfolder shows its contents in place.
struct FolderBrowserView: View {
    let title: String
    let sortOrderChanged: (FolderSortOrder) -> Void
    let dismiss: () -> Void

    @State private var model: FolderBrowserModel

    init(
        folder: FolderItem,
        sortOrderChanged: @escaping (FolderSortOrder) -> Void,
        dismiss: @escaping () -> Void
    ) {
        title = folder.displayName
        self.sortOrderChanged = sortOrderChanged
        self.dismiss = dismiss
        _model = State(initialValue: FolderBrowserModel(root: folder.url, sortOrder: folder.sortOrder ?? .name))
    }

    private static let maxColumns = 5
    private static let minColumns = 3
    private static let spacing: CGFloat = 4
    private static let maxGridHeight: CGFloat = 380

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
            footer
        }
        .padding(12)
        .frame(minWidth: Self.gridWidth(columns: Self.minColumns), alignment: .leading)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if model.canGoBack {
                Button {
                    model.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .help("Back")
                .accessibilityLabel("Back")
            }
            Text(model.canGoBack ? FileManager.default.displayName(atPath: model.folder.path) : title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Menu {
                Picker("Sort By", selection: sortOrder) {
                    ForEach(FolderSortOrder.allCases, id: \.self) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sort By")
            .accessibilityLabel("Sort By")
        }
    }

    private var sortOrder: Binding<FolderSortOrder> {
        Binding(
            get: { model.sortOrder },
            set: { order in
                model.sort(by: order)
                sortOrderChanged(order)
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        if let contents = model.contents {
            if contents.entries.isEmpty {
                placeholder("This folder is empty.")
            } else {
                grid(contents.entries)
            }
        } else if model.failed {
            placeholder("OpenDock can't read this folder.")
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: FolderEntryCell.size.height)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: FolderEntryCell.size.height)
    }

    /// Lazy, so only the cells scrolled into view load their icons.
    private func grid(_ entries: [FolderEntry]) -> some View {
        let columns = min(max(entries.count, Self.minColumns), Self.maxColumns)
        let rows = (entries.count + columns - 1) / columns
        let height = CGFloat(rows) * FolderEntryCell.size.height + CGFloat(rows - 1) * Self.spacing
        return ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(FolderEntryCell.size.width), spacing: Self.spacing), count: columns),
                spacing: Self.spacing
            ) {
                ForEach(entries) { entry in
                    FolderEntryCell(entry: entry, click: { click(entry) }, open: { open(entry.url) })
                }
            }
        }
        .frame(width: Self.gridWidth(columns: columns), height: min(height, Self.maxGridHeight))
    }

    private static func gridWidth(columns: Int) -> CGFloat {
        CGFloat(columns) * FolderEntryCell.size.width + CGFloat(columns - 1) * spacing
    }

    private var footer: some View {
        HStack {
            if let contents = model.contents, contents.isTruncated {
                Text("Showing \(contents.entries.count.formatted()) of \(contents.totalCount.formatted()) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Open in Finder") { open(model.folder) }
                .folderBrowserButtonStyle()
        }
    }

    private func click(_ entry: FolderEntry) {
        if entry.isFolder {
            model.browse(into: entry.url)
        } else {
            open(entry.url)
        }
    }

    /// Opens files in their apps and folders in Finder.
    private func open(_ url: URL) {
        AppLauncher.open(url: url)
        dismiss()
    }
}

/// An item's icon and name. It can be dragged out like a file in Finder.
private struct FolderEntryCell: View {
    let entry: FolderEntry
    let click: () -> Void
    let open: () -> Void

    static let size = CGSize(width: 84, height: 92)
    private static let iconSize: CGFloat = 48

    @State private var icon: NSImage?
    @State private var isHovered = false

    var body: some View {
        Button(action: click) {
            VStack(spacing: 4) {
                Group {
                    if let icon {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: Self.iconSize, height: Self.iconSize)
                Text(entry.name)
                    .font(.caption)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)
            }
            .padding(6)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.primary.opacity(isHovered ? 0.1 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(entry.name)
        .task(id: entry.url) {
            let image = NSWorkspace.shared.icon(forFile: entry.url.path)
            // Sized up so the 48-point icon is drawn from a sharp representation on Retina.
            image.size = NSSize(width: 128, height: 128)
            icon = image
        }
        .onDrag { NSItemProvider(object: entry.url as NSURL) }
        .contextMenu {
            Button("Open", action: open)
            Button("Show in Finder") { AppLauncher.revealInFinder(entry.url) }
        }
    }
}

extension View {
    /// Liquid Glass on macOS 26, where the popover around it is glass too; a bordered
    /// button on the frosted popovers of earlier versions.
    @ViewBuilder
    fileprivate func folderBrowserButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}
