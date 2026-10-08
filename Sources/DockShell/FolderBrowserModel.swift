import DockCore
import Foundation
import Observation
import SystemServices

/// What a folder's popover shows: the contents of the folder, or of a subfolder browsed
/// into, kept current while the popover is open.
@Observable
final class FolderBrowserModel {
    let root: URL
    /// Subfolders browsed into, innermost last.
    private(set) var path: [URL] = []
    private(set) var sortOrder: FolderSortOrder
    /// Nil while loading or when the folder can't be read.
    private(set) var contents: FolderContents?
    private(set) var failed = false

    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(root: URL, sortOrder: FolderSortOrder) {
        self.root = root
        self.sortOrder = sortOrder
    }

    var folder: URL { path.last ?? root }
    var canGoBack: Bool { !path.isEmpty }

    func start() {
        watchFolder()
        reload()
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        loadTask?.cancel()
        loadTask = nil
    }

    func browse(into subfolder: URL) {
        path.append(subfolder)
        folderChanged()
    }

    func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
        folderChanged()
    }

    func sort(by order: FolderSortOrder) {
        guard order != sortOrder else { return }
        sortOrder = order
        reload()
    }

    private func folderChanged() {
        contents = nil
        failed = false
        watchFolder()
        reload()
    }

    private func watchFolder() {
        watcher?.stop()
        // Saving or downloading a file can change the folder several times in a row.
        watcher = FolderWatcher(url: folder) { [weak self] in self?.reload(after: .milliseconds(150)) }
    }

    private func reload(after delay: Duration = .zero) {
        loadTask?.cancel()
        let folder = folder
        let order = sortOrder
        loadTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            let listed = await Task.detached(priority: .userInitiated) {
                try? FolderListing.contents(of: folder, sortedBy: order)
            }.value
            guard let self, !Task.isCancelled else { return }
            contents = listed
            failed = listed == nil
        }
    }
}
