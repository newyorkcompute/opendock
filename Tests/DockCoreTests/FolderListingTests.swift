import Foundation
import Testing

@testable import DockCore

@Suite("Folder listing")
struct FolderListingTests {
    private func entry(
        _ name: String, added: TimeInterval? = nil, modified: TimeInterval? = nil, kind: String? = nil
    ) -> FolderEntry {
        FolderEntry(
            url: URL(fileURLWithPath: "/tmp/stack/\(name)"),
            name: name,
            dateAdded: added.map(Date.init(timeIntervalSince1970:)),
            dateModified: modified.map(Date.init(timeIntervalSince1970:)),
            kind: kind
        )
    }

    private func names(_ entries: [FolderEntry], by order: FolderSortOrder) -> [String] {
        FolderListing.sorted(entries, by: order).map(\.name)
    }

    @Test func sortsNamesLikeFinder() {
        let entries = [entry("File 10"), entry("b"), entry("File 2"), entry("A")]
        #expect(names(entries, by: .name) == ["A", "b", "File 2", "File 10"])
    }

    @Test func sortsByDateAddedNewestFirst() {
        let entries = [entry("old", added: 100), entry("undated"), entry("new", added: 300), entry("mid", added: 200)]
        #expect(names(entries, by: .dateAdded) == ["new", "mid", "old", "undated"])
    }

    @Test func sortsByDateModifiedNewestFirst() {
        let entries = [entry("a", modified: 100), entry("b", modified: 300), entry("c")]
        #expect(names(entries, by: .dateModified) == ["b", "a", "c"])
    }

    @Test func sortsByKindThenName() {
        let entries = [
            entry("z", kind: "PDF document"), entry("b", kind: "Folder"), entry("a", kind: "PDF document"),
            entry("c", kind: "Folder"),
        ]
        #expect(names(entries, by: .kind) == ["b", "c", "a", "z"])
    }

    @Test func breaksTiesByName() {
        let entries = [entry("b", added: 100), entry("a", added: 100)]
        #expect(names(entries, by: .dateAdded) == ["a", "b"])
    }

    @Test func listsVisibleItemsOfAFolder() throws {
        let folder = try makeFolder(files: ["b.txt", ".hidden", "a.txt"], folders: ["Sub"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let contents = try FolderListing.contents(of: folder, sortedBy: .name)
        #expect(contents.entries.map(\.url.lastPathComponent) == ["a.txt", "b.txt", "Sub"])
        #expect(contents.totalCount == 3)
        #expect(!contents.isTruncated)
        #expect(contents.entries.map(\.isFolder) == [false, false, true])
    }

    @Test func cutsOffLargeFoldersAfterSorting() throws {
        let files = (1 ... 12).map { "File \($0).txt" }
        let folder = try makeFolder(files: files.shuffled())
        defer { try? FileManager.default.removeItem(at: folder) }

        let contents = try FolderListing.contents(of: folder, sortedBy: .name, limit: 5)
        #expect(contents.entries.map(\.url.lastPathComponent) == Array(files.prefix(5)))
        #expect(contents.totalCount == 12)
        #expect(contents.isTruncated)
    }

    @Test func onlyFoldersAreBrowsable() throws {
        let folder = try makeFolder(files: ["note.txt"], folders: ["Sub"])
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(FolderListing.isBrowsable(folder))
        #expect(FolderListing.isBrowsable(folder.appendingPathComponent("Sub")))
        #expect(!FolderListing.isBrowsable(folder.appendingPathComponent("note.txt")))
        #expect(!FolderListing.isBrowsable(folder.appendingPathComponent("missing")))
    }

    @Test func missingFolderThrows() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(throws: (any Error).self) { try FolderListing.contents(of: missing, sortedBy: .name) }
    }

    // MARK: - Persistence

    @Test func folderItemKeepsItsSortOrder() throws {
        let item = DockItem(kind: .folder(FolderItem(url: URL(fileURLWithPath: "/tmp/x"), sortOrder: .dateAdded)))
        let decoded = try JSONDecoder().decode(DockItem.self, from: JSONEncoder().encode(item))
        #expect(decoded.folderItem?.sortOrder == .dateAdded)
    }

    @Test func folderItemWithoutSortOrderStillLoads() throws {
        let json = #"{"id":"6F1A2B3C-0000-4000-8000-000000000001","kind":{"folder":{"_0":{"url":"file:///tmp/x"}}}}"#
        let decoded = try JSONDecoder().decode(DockItem.self, from: Data(json.utf8))
        #expect(decoded.folderItem?.url.path == "/tmp/x")
        #expect(decoded.folderItem?.sortOrder == nil)
    }

    @Test func unknownSortOrderFallsBackToDefault() throws {
        let json = #"{"url":"file:///tmp/x","customName":"X","sortOrder":"size"}"#
        let decoded = try JSONDecoder().decode(FolderItem.self, from: Data(json.utf8))
        #expect(decoded.customName == "X")
        #expect(decoded.sortOrder == nil)
    }

    private func makeFolder(files: [String], folders: [String] = []) throws -> URL {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory.appendingPathComponent("FolderListingTests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in folders {
            try fileManager.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: false)
        }
        for name in files {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        return folder
    }
}
