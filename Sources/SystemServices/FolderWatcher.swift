import Foundation

/// Tells when items are added to, removed from, or renamed in a folder, or the folder
/// itself is moved or deleted. Changes to the contents of files in it don't count.
@MainActor
public final class FolderWatcher {
    private var source: (any DispatchSourceFileSystemObject)?

    /// Nil if the folder can't be opened. `onChange` runs on the main actor, and may run
    /// several times for one change.
    public init?(url: URL, onChange: @escaping @MainActor () -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .link], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { onChange() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
    }

    isolated deinit {
        stop()
    }
}
