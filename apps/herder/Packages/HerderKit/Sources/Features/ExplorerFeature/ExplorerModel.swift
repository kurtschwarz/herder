import Clients
import Foundation
import Models
import Observation
import WorktreeState

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

    /// The folder the tree is rooted at, in the app's one path spelling.
    /// Always open; `nil` shows nothing.
    public private(set) var root: URL?

    /// `root` as a key, so every path below it can be keyed by appending
    /// instead of resolving again.
    private var rootKey: PathKey?

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

    /// What git says about the whole worktree, however much of it is open.
    public private(set) var status: WorktreeStatus = .empty

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
        // Canonicalised here, at the edge of the tree, so `listings` and the
        // keys git and the file watcher hand back are all the one spelling and
        // compare by construction.
        let key = url.map(PathKey.init)
        let url = key?.url
        guard url != root else { return }
        root = url
        rootKey = key
        listings = [:]
        status = .empty
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

    /// Re-reads the root and every open folder, then asks git about the tree.
    /// Files change in a terminal while the app is in the background, so this is
    /// what keeps the tree honest.
    ///
    /// The listings go up before git is asked, so a slow git delays the marks
    /// and not the folders.
    public func refresh() async {
        guard let root else { return }
        for folder in [root] + expanded.sorted(by: { $0.path < $1.path }) {
            await read(folder)
        }
        await readStatus()
    }

    /// Reads `folder` and shows it.
    private func read(_ folder: URL) async {
        let origin = root
        let entries: [DirectoryEntry]
        do {
            entries = Self.sorted(try await files.children(of: folder))
        } catch {
            // The task that asked was cancelled, which says nothing about the
            // folder.
            guard !Task.isCancelled, root == origin else { return }
            listings[folder] = .unreadable
            return
        }
        // The root changed while the read was out: its answer is for a tree
        // that is no longer showing.
        guard root == origin else { return }
        // A listing that came back the same is not assigned. Writing to a file
        // inside an open folder changes nothing about what is in that folder,
        // so a build in watch mode would otherwise re-flatten the whole tree
        // over and over for no visible difference.
        guard listings[folder] != .loaded(entries) else { return }
        listings[folder] = .loaded(entries)
    }

    /// Asks git about the whole worktree. One subprocess, however many folders
    /// are open, and it covers folders nobody has opened too: that is what lets
    /// a closed folder say something inside it changed.
    private func readStatus() async {
        guard let root else { return }
        let origin = root
        let answer: GitWorktreeStatus
        do {
            answer = try await git.status(in: root)
        } catch {
            // Git could not be asked, which says nothing about the files: keep
            // what is already marked rather than calling the tree clean.
            return
        }
        guard self.root == origin else { return }
        let derived = WorktreeStatus(answer)
        guard status != derived else { return }
        status = derived
    }

    /// Keys a path inside the tree. Resolved by construction rather than by
    /// another `realpath`: the root was canonicalised when it was set, and
    /// everything under it was built by appending to that.
    private func key(_ url: URL) -> PathKey {
        PathKey(resolved: url.path(percentEncoded: false))
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
                // Everything inside an ignored folder is ignored with it. The
                // flag rides down the recursion rather than being asked again
                // per row, which would walk back up to the root each time.
                let isIgnored = underIgnored || status.isIgnored(key(entry.url))
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
