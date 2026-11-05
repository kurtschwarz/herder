import Clients
import Foundation
import Observation

/// One line of the flattened tree.
public struct ExplorerRow: Identifiable, Equatable {
    public enum Kind: Equatable {
        case entry(DirectoryEntry)
        /// Stands in for the contents of a folder that could not be read.
        case unreadable
        /// The name field of a file or folder that is about to be made.
        case creating(isDirectory: Bool)
    }

    public var kind: Kind
    public var depth: Int
    public var parent: URL

    /// Tells one name field from the next. Without it a second field in the
    /// same folder reuses the first's view state, including its "already
    /// finished" flag, and never commits.
    var creation: UUID?

    /// Git ignores it, or a folder around it. Drawn faded.
    var isIgnored = false

    public var id: String {
        switch kind {
        case .entry(let entry): entry.url.absoluteString
        case .unreadable: parent.absoluteString + "#unreadable"
        case .creating: parent.absoluteString + "#creating-" + (creation?.uuidString ?? "")
        }
    }
}

private extension ExplorerRow {
    var isDirectoryField: Bool {
        if case .creating(let isDirectory) = kind { isDirectory } else { false }
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
    private let git: any GitClient

    /// The folder the tree is rooted at. Always open; `nil` shows nothing.
    public private(set) var root: URL?

    public private(set) var listings: [URL: Listing] = [:]

    /// Open folders below the root.
    public private(set) var expanded: Set<URL> = []

    /// The file the user last clicked.
    public private(set) var selected: URL?

    /// The item whose name is being edited in place.
    public private(set) var renaming: URL?

    /// A new file or folder being named, before anything exists on disk.
    public struct Creation: Equatable {
        public var parent: URL
        public var isDirectory: Bool
        var id = UUID()
    }

    public private(set) var creating: Creation?

    /// Everything in the folders read so far that git ignores.
    public private(set) var ignored: Set<URL> = []

    public init(files: any FileClient, git: any GitClient) {
        self.files = files
        self.git = git
    }

    /// Whether a name field is open. Return belongs to that field, not to the
    /// tree behind it.
    public var isEditingName: Bool { renaming != nil || creating != nil }

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
        ignored = []
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
        creating = nil
        renaming = url
    }

    /// Opens a name field inside `folder`, opening the folder if it is closed.
    /// Nothing is made until the name is committed.
    public func beginCreating(in folder: URL, isDirectory: Bool) async {
        renaming = nil
        if folder != root { expanded.insert(folder) }
        // Before the read, so the field appears as the listing does and not
        // after git has answered as well.
        creating = Creation(parent: folder, isDirectory: isDirectory)
        if listings[folder] == nil { await read(folder) }
    }

    public func cancelCreating() {
        creating = nil
    }

    /// Makes what the name field describes and shows it. A blank or unusable
    /// name, or a refusal from the disk (the name is taken, say), makes
    /// nothing. A new file is selected; a new folder is left closed.
    public func commitCreating(named name: String) async {
        guard let creation = creating else { return }
        creating = nil
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else { return }

        let url = creation.parent.appending(
            path: name,
            directoryHint: creation.isDirectory ? .isDirectory : .notDirectory
        )
        do {
            try await files.create(url, isDirectory: creation.isDirectory)
        } catch {
            return
        }
        if !creation.isDirectory { selected = url }
        await refresh()
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

    /// Reads `folder` and shows it, then fades what git ignores. The listing
    /// goes up before git is asked, so a slow git delays the fade and not the
    /// folder.
    private func read(_ folder: URL) async {
        let origin = root
        let entries: [DirectoryEntry]
        do {
            entries = Self.sorted(try await files.children(of: folder))
        } catch {
            // The task that asked was cancelled, which says nothing about the
            // folder.
            guard !Task.isCancelled, root == origin else { return }
            forgetIgnored(in: folder)
            listings[folder] = .unreadable
            return
        }
        // The root changed while the read was out: its answer is for a tree
        // that is no longer showing.
        guard root == origin else { return }
        let before = listings[folder]
        listings[folder] = .loaded(entries)

        // Inside an ignored folder everything is faded already, so asking git
        // about each child of `node_modules` would be wasted.
        if isInsideIgnored(folder) {
            ignored.subtract(entries.map(\.url))
            return
        }
        let flagged: Set<URL>
        do {
            flagged = try await git.ignored(entries, in: folder)
        } catch {
            // Git could not be asked, which says nothing about the files: keep
            // what was faded.
            return
        }
        // A newer read of this folder, or another root, overtook this one.
        guard root == origin, listings[folder] == .loaded(entries) else { return }
        if case .loaded(let old)? = before { ignored.subtract(old.map(\.url)) }
        ignored.subtract(entries.map(\.url))
        ignored.formUnion(flagged)
    }

    private func forgetIgnored(in folder: URL) {
        if case .loaded(let old)? = listings[folder] { ignored.subtract(old.map(\.url)) }
    }

    /// Whether `folder`, or a folder between it and the root, is ignored.
    private func isInsideIgnored(_ folder: URL) -> Bool {
        // A folder's URL may or may not end in a slash, depending on where it
        // came from, so compare paths without one.
        func key(_ url: URL) -> String {
            var path = url.path(percentEncoded: false)
            while path.count > 1, path.hasSuffix("/") { path.removeLast() }
            return path
        }
        let paths = Set(ignored.map(key))
        let rootPath = root.map(key)
        var current = folder
        while true {
            let path = key(current)
            if paths.contains(path) { return true }
            if path == rootPath || path == "/" { return false }
            current = current.deletingLastPathComponent()
        }
    }

    private func rows(in folder: URL, depth: Int, underIgnored: Bool = false) -> [ExplorerRow] {
        switch listings[folder] {
        case .loaded(let entries):
            let field = creating.flatMap { $0.parent == folder ? $0 : nil }
                .map {
                    ExplorerRow(kind: .creating(isDirectory: $0.isDirectory), depth: depth, parent: folder, creation: $0.id)
                }
            var result: [ExplorerRow] = []
            var placed = field == nil
            for entry in entries {
                // A new folder leads the folders, a new file leads the files.
                if !placed, let field, field.isDirectoryField || !entry.isDirectory {
                    result.append(field)
                    placed = true
                }
                // Everything inside an ignored folder is ignored with it.
                let isIgnored = underIgnored || ignored.contains(entry.url)
                var row = ExplorerRow(kind: .entry(entry), depth: depth, parent: folder)
                row.isIgnored = isIgnored
                result.append(row)
                if entry.isDirectory, expanded.contains(entry.url) {
                    result += rows(in: entry.url, depth: depth + 1, underIgnored: isIgnored)
                }
            }
            if !placed, let field { result.append(field) }
            return result
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
