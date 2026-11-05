import Core
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

    /// The mark it carries for what git says about it, or for what changed
    /// inside it when it is a closed folder.
    var mark: GitMark?

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

/// The file tree of one worktree.
///
/// Owns what the pane does — which folders are open, what is selected, what is
/// being named — and reads the files and the git state from the worktree's
/// ``Workspace``, which is shared and kept fresh by a watcher. Expansion
/// lives here and is dropped with the root.
@Observable
public final class ExplorerModel {
    private let store: WorkspaceRegistry

    /// The worktree being shown, or `nil` when none is selected.
    public private(set) var worktree: Workspace?

    private var registration: Workspace.Registration?

    /// The folder the tree is rooted at. Always open; `nil` shows nothing.
    public var root: URL? { worktree?.root.url }

    /// Open folders below the root, kept on the workspace so that switching
    /// away and back does not close everything the user opened. See
    /// ``ExplorerUIState``.
    ///
    /// A computed property over that state rather than a stored one, so every
    /// reader below is unchanged and there is exactly one place the tree's
    /// expansion lives. Empty, and silently unwritable, when no worktree is
    /// shown — there is nothing for expansion to be relative to.
    private var expanded: Set<PathKey> {
        get { worktree?.uiState(ExplorerUIState.self).expanded ?? [] }
        set { worktree?.uiState(ExplorerUIState.self).expanded = newValue }
    }

    /// The file the user last clicked.
    public private(set) var selected: URL?

    /// The item whose name is being edited in place.
    public private(set) var renaming: URL?

    /// A new file or folder being named, before anything exists on disk.
    public struct Creation: Equatable {
        public var parent: PathKey
        public var isDirectory: Bool
        var id = UUID()
    }

    public private(set) var creating: Creation?

    /// What git says about the whole worktree, however much of it is open.
    public var status: WorktreeStatus { worktree?.status ?? .empty }

    public init(store: WorkspaceRegistry) {
        self.store = store
    }

    /// Whether a name field is open. Return belongs to that field, not to the
    /// tree behind it.
    public var isEditingName: Bool { renaming != nil || creating != nil }

    public var canCollapse: Bool { !expanded.isEmpty }

    /// The tree as the list draws it: every open folder followed by its
    /// children, one row per line.
    public var rows: [ExplorerRow] {
        guard let worktree, worktree.isAvailable else { return [] }
        return rows(in: worktree.root, depth: 0)
    }

    public func listing(of url: URL) -> Workspace.Listing? {
        worktree?.listing(of: Self.key(url))
    }

    /// Points the tree at a new worktree, or at nothing. Does nothing when it
    /// is already the root, so a repeat selection keeps what is open.
    public func setRoot(_ url: URL?) async {
        let key = url.map(PathKey.init)
        guard key != worktree?.root else { return }

        registration?.cancel()
        registration = nil
        // Expansion is not cleared: it belongs to the worktree being left, not
        // to this pane, and it is still that worktree's when the user comes
        // back. What is cleared is what was about the pane's last contents.
        selected = nil
        renaming = nil
        creating = nil

        let state = await store.select(key?.url)
        // Weak, or the state would hold this model which holds the store which
        // holds the state.
        registration = state?.observe(onChange: { [weak self] in self?.dropWhatHasGone() })
        // Held before the first read, so the folders show as they are read
        // rather than all at once once git has answered as well.
        worktree = state
        await state?.refresh()
    }

    /// Whether drains may run for the worktree. Suspended while the window is
    /// not in front: changes keep accumulating and are acted on in one go when
    /// it comes back, because the worst storms happen while the user is in a
    /// terminal running the build that causes them.
    public func setWatching(_ enabled: Bool) {
        store.setDraining(enabled)
    }

    public func isExpanded(_ folder: URL) -> Bool {
        expanded.contains(Self.key(folder))
    }

    public func toggle(_ folder: URL) async {
        let key = Self.key(folder)
        if expanded.remove(key) == nil {
            expanded.insert(key)
            await worktree?.open(key)
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
        guard let worktree else { return }
        let key = Self.key(folder)
        renaming = nil
        if key != worktree.root { expanded.insert(key) }
        // Before the read, so the field appears as the listing does and not
        // after git has answered as well.
        creating = Creation(parent: key, isDirectory: isDirectory)
        await worktree.open(key)
    }

    public func cancelCreating() {
        creating = nil
    }

    /// Makes what the name field describes and shows it. A blank or unusable
    /// name, or a refusal from the disk (the name is taken, say), makes
    /// nothing. A new file is selected; a new folder is left closed.
    public func commitCreating(named name: String) async {
        guard let creation = creating, let worktree else { return }
        creating = nil
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else { return }

        let url = creation.parent.url.appending(
            path: name,
            directoryHint: creation.isDirectory ? .isDirectory : .notDirectory
        )
        do {
            try await worktree.create(url, isDirectory: creation.isDirectory)
        } catch {
            return
        }
        if !creation.isDirectory { selected = url }
    }

    public func cancelRenaming() {
        renaming = nil
    }

    /// Renames `entry` on disk, then re-reads so the tree shows the result. A
    /// blank, unchanged or unusable name, or a refusal from the disk (the name
    /// is taken, say), leaves everything as it was.
    public func commitRename(_ entry: DirectoryEntry, to name: String) async {
        renaming = nil
        guard let worktree else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != entry.name, !name.contains("/") else { return }

        let destination = entry.url.deletingLastPathComponent()
            .appending(path: name, directoryHint: entry.isDirectory ? .isDirectory : .notDirectory)
        // What was open under a renamed folder is still open under its new name.
        // Rebased before the move rather than after, because the move re-reads
        // the folder, and that read is what would otherwise find the old name
        // gone and drop the selection with it.
        let old = Self.key(entry.url)
        let new = Self.key(destination)
        let openBefore = expanded
        let selectedBefore = selected
        expanded = Set(expanded.map { Workspace.moved($0, from: old, to: new) })
        if let selected { self.selected = Workspace.moved(Self.key(selected), from: old, to: new).url }

        do {
            try await worktree.move(entry.url, to: destination)
        } catch {
            expanded = openBefore
            selected = selectedBefore
        }
    }

    /// Closes every folder below the root.
    public func collapseAll() {
        expanded = []
    }

    /// Re-reads the root and every open folder, then asks git about the tree.
    public func refresh() async {
        await worktree?.refresh()
    }

    /// Keys a path inside the tree. Resolved by construction rather than by
    /// another `realpath`: the root was canonicalised when it was selected, and
    /// everything under it was built by appending to that.
    private static func key(_ url: URL) -> PathKey {
        PathKey(canonical: url.path(percentEncoded: false))
    }

    /// Drops a selection or a rename whose file has gone.
    ///
    /// With changes arriving continuously these go stale under the user, which
    /// they could not when the tree only ever moved on a window focus.
    /// `creating` is left alone: the user is part-way through typing and its
    /// path does not exist yet by definition.
    private func dropWhatHasGone() {
        if let selected, !isStillThere(selected) { self.selected = nil }
        if let renaming, !isStillThere(renaming) { self.renaming = nil }
    }

    /// Unknown counts as there: leaving something alone beats dropping what is
    /// probably fine.
    private func isStillThere(_ url: URL) -> Bool {
        worktree?.exists(Self.key(url)) ?? true
    }

    private func rows(in folder: PathKey, depth: Int, underIgnored: Bool = false) -> [ExplorerRow] {
        guard let worktree else { return [] }
        let parent = folder.url

        switch worktree.listing(of: folder) {
        case .loaded(let entries):
            let field = creating.flatMap { $0.parent == folder ? $0 : nil }
                .map {
                    ExplorerRow(kind: .creating(isDirectory: $0.isDirectory), depth: depth, parent: parent, creation: $0.id)
                }
            var result: [ExplorerRow] = []
            var placed = field == nil
            for entry in entries {
                // A new folder leads the folders, a new file leads the files.
                if !placed, let field, field.isDirectoryField || !entry.isDirectory {
                    result.append(field)
                    placed = true
                }
                let key = Self.key(entry.url)
                let isOpen = entry.isDirectory && expanded.contains(key)
                // Everything inside an ignored folder is ignored with it. The
                // flag rides down the recursion rather than being asked again
                // per row, which would walk back up to the root each time.
                let isIgnored = underIgnored || worktree.status.isIgnored(key)
                var row = ExplorerRow(kind: .entry(entry), depth: depth, parent: parent)
                row.isIgnored = isIgnored
                row.mark = isIgnored ? nil : mark(of: key, isDirectory: entry.isDirectory, isOpen: isOpen)
                result.append(row)
                if isOpen {
                    result += rows(in: key, depth: depth + 1, underIgnored: isIgnored)
                }
            }
            if !placed, let field { result.append(field) }
            return result
        case .unreadable:
            return [ExplorerRow(kind: .unreadable, depth: depth, parent: parent)]
        case nil:
            return []
        }
    }

    /// A file wears what git says about it. A folder wears what changed inside
    /// it, and only while it is closed: once it is open, the rows inside say it
    /// better than a mark on the folder could.
    private func mark(of path: PathKey, isDirectory: Bool, isOpen: Bool) -> GitMark? {
        guard let worktree else { return nil }
        if isDirectory {
            guard !isOpen else { return nil }
            return worktree.status.rollup(of: path)
        }
        return worktree.status.status(of: path).flatMap(GitMark.init)
    }
}
