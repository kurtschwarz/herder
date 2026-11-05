import Clients
import Foundation
import Observation

/// One line of the flattened tree.
public struct ExplorerRow: Identifiable, Equatable {
    public enum Kind: Equatable {
        case entry(DirectoryEntry)
        /// Stands in for the contents of a folder that could not be read.
        case unreadable
    }

    public var kind: Kind
    public var depth: Int
    public var parent: URL

    public var id: String {
        switch kind {
        case .entry(let entry): entry.url.absoluteString
        case .unreadable: parent.absoluteString + "#unreadable"
        }
    }
}

/// The file tree of one folder.
///
/// Folders are read the first time they are opened and kept until the next
/// refresh, so a repository's `node_modules` costs nothing until someone looks
/// inside it. Expansion lives here and is dropped with the root.
@Observable
public final class ExplorerModel {
    /// What reading a folder came to. A failed read is its own state because an
    /// empty list would claim the folder has nothing in it.
    public enum Listing: Equatable {
        case loaded([DirectoryEntry])
        case unreadable
    }

    /// Git's own folders: machinery, not the user's files.
    private static let hidden: Set<String> = [".git", ".bare"]

    private let files: any FileClient

    /// The folder the tree is rooted at. Always open; `nil` shows nothing.
    public private(set) var root: URL?

    public private(set) var listings: [URL: Listing] = [:]

    /// Open folders below the root.
    public private(set) var expanded: Set<URL> = []

    /// The file the user last clicked.
    public private(set) var selected: URL?

    /// The item whose name is being edited in place.
    public private(set) var renaming: URL?

    public init(files: any FileClient) {
        self.files = files
    }

    public var canCollapse: Bool { !expanded.isEmpty }

    /// The tree as the list draws it: every open folder followed by its
    /// children, one row per line.
    public var rows: [ExplorerRow] {
        guard let root else { return [] }
        return rows(in: root, depth: 0)
    }

    /// Points the tree at a new folder, or at nothing. Does nothing when `url`
    /// is already the root, so a repeat selection keeps what is open.
    public func setRoot(_ url: URL?) async {
        guard url != root else { return }
        root = url
        listings = [:]
        expanded = []
        selected = nil
        await refresh()
    }

    public func isExpanded(_ folder: URL) -> Bool {
        expanded.contains(folder)
    }

    public func toggle(_ folder: URL) async {
        if expanded.remove(folder) == nil {
            expanded.insert(folder)
            if listings[folder] == nil { await read(folder) }
        }
    }

    public func select(_ file: URL) {
        selected = file
    }

    public func beginRenaming(_ url: URL) {
        renaming = url
    }

    public func cancelRenaming() {
        renaming = nil
    }

    /// Renames `entry` on disk, then re-reads so the tree shows the result. A
    /// blank, unchanged or unusable name, or a refusal from the disk (the name
    /// is taken, say), leaves everything as it was.
    public func commitRename(_ entry: DirectoryEntry, to name: String) async {
        renaming = nil
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != entry.name, !name.contains("/") else { return }

        let destination = entry.url.deletingLastPathComponent()
            .appending(path: name, directoryHint: entry.isDirectory ? .isDirectory : .notDirectory)
        do {
            try await files.move(entry.url, to: destination)
        } catch {
            return
        }

        // What was open under a renamed folder is still open under its new name.
        expanded = Set(expanded.map { Self.moved($0, from: entry.url, to: destination) })
        listings = Dictionary(
            listings.map { (Self.moved($0.key, from: entry.url, to: destination), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        if let selected { self.selected = Self.moved(selected, from: entry.url, to: destination) }
        await refresh()
    }

    /// `url` rebased onto `new` if it is `old` or lies inside it.
    private static func moved(_ url: URL, from old: URL, to new: URL) -> URL {
        let oldPath = old.path(percentEncoded: false)
        let path = url.path(percentEncoded: false)
        if path == oldPath { return new }
        guard path.hasPrefix(oldPath + "/") else { return url }
        return new.appending(
            path: String(path.dropFirst(oldPath.count + 1)),
            directoryHint: url.hasDirectoryPath ? .isDirectory : .notDirectory
        )
    }

    /// Closes every folder below the root.
    public func collapseAll() {
        expanded = []
    }

    /// Re-reads the root and every open folder. Files change in a terminal while
    /// the app is in the background, so this is what keeps the tree honest.
    public func refresh() async {
        guard let root else { return }
        for folder in [root] + expanded.sorted(by: { $0.path < $1.path }) {
            await read(folder)
        }
    }

    private func read(_ folder: URL) async {
        let origin = root
        let listing: Listing
        do {
            let entries = try await files.children(of: folder)
            listing = .loaded(Self.sorted(entries))
        } catch {
            // The task that asked was cancelled, which says nothing about the
            // folder.
            guard !Task.isCancelled else { return }
            listing = .unreadable
        }
        // The root changed while the read was out: its answer is for a tree
        // that is no longer showing.
        guard root == origin else { return }
        listings[folder] = listing
    }

    private func rows(in folder: URL, depth: Int) -> [ExplorerRow] {
        switch listings[folder] {
        case .loaded(let entries):
            return entries.flatMap { entry -> [ExplorerRow] in
                let row = ExplorerRow(kind: .entry(entry), depth: depth, parent: folder)
                guard entry.isDirectory, expanded.contains(entry.url) else { return [row] }
                return [row] + rows(in: entry.url, depth: depth + 1)
            }
        case .unreadable:
            return [ExplorerRow(kind: .unreadable, depth: depth, parent: folder)]
        case nil:
            return []
        }
    }

    /// Folders before files, each group by name regardless of case.
    private static func sorted(_ entries: [DirectoryEntry]) -> [DirectoryEntry] {
        entries
            .filter { !hidden.contains($0.name) }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}
