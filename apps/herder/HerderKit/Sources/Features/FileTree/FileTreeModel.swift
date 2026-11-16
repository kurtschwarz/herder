import Core
import Foundation
import Observation

/// One line of the flattened tree.
struct FileTreeRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case entry(DirectoryEntry)
        /// Stands in for the contents of a folder that could not be read.
        case unreadable
        /// The name field of a file or folder that is about to be made.
        case creating(isDirectory: Bool)
    }

    var kind: Kind
    var depth: Int
    var parent: URL

    /// Tells one name field from the next. Without it a second field in the
    /// same folder reuses the first's view state, including its "already
    /// finished" flag, and never commits.
    var creation: UUID?

    /// Git ignores it, or a folder around it. Drawn faded.
    var isIgnored = false

    /// The letter it carries for what git says about it, or for what changed
    /// inside it when it is a closed folder. Open folders carry none.
    var mark: GitMark?

    /// What colours its name: what git says about it, or the most severe change
    /// inside it when it is a folder. Unlike ``mark`` it does not depend on
    /// whether a folder is open.
    var tint: GitMark?

    var id: String {
        switch kind {
        case .entry(let entry): entry.url.absoluteString
        case .unreadable: parent.absoluteString + "#unreadable"
        case .creating: parent.absoluteString + "#creating-" + (creation?.uuidString ?? "")
        }
    }
}

private extension FileTreeRow {
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
public final class FileTreeModel {
    private let store: WorkspaceRegistry

    /// The worktree being shown, or `nil` when none is selected.
    private(set) var worktree: Workspace?

    private var registration: Workspace.Registration?

    /// The folder the tree is rooted at. Always open; `nil` shows nothing.
    var root: URL? { worktree?.root.url }

    /// Open folders below the root, kept on the workspace so that switching
    /// away and back does not close everything the user opened. See
    /// ``FileTreeUIState``.
    ///
    /// A computed property over that state rather than a stored one, so every
    /// reader below is unchanged and there is exactly one place the tree's
    /// expansion lives. Empty, and silently unwritable, when no worktree is
    /// shown — there is nothing for expansion to be relative to.
    private var expanded: Set<PathKey> {
        get { worktree?.uiState(FileTreeUIState.self).expanded ?? [] }
        set {
            worktree?.uiState(FileTreeUIState.self).expanded = newValue
            // Observation reports reads, not writes, so the workspace cannot
            // notice this for itself.
            worktree?.scheduleSnapshotSave()
        }
    }

    /// The file the user last clicked.
    public private(set) var selected: URL?

    /// The item whose name is being edited in place.
    private(set) var renaming: URL?

    /// A new file or folder being named, before anything exists on disk.
    struct Creation: Equatable {
        var parent: PathKey
        var isDirectory: Bool
        var id = UUID()
    }

    private(set) var creating: Creation?

    /// The item waiting on an answer to "delete it for good?". Moving to the
    /// Trash can be undone and never waits.
    private(set) var pendingDelete: DirectoryEntry?

    /// What git says about the whole worktree, however much of it is open.
    var status: WorktreeStatus { worktree?.status ?? .empty }

    public init(store: WorkspaceRegistry) {
        self.store = store
    }

    /// Whether a name field is open. Return belongs to that field, not to the
    /// tree behind it.
    var isEditingName: Bool { renaming != nil || creating != nil }

    var canCollapse: Bool { !expanded.isEmpty }

    /// The tree as the list draws it: every open folder followed by its
    /// children, one row per line.
    var rows: [FileTreeRow] {
        guard let worktree, worktree.isAvailable else { return [] }
        return rows(in: worktree.root, depth: 0)
    }

    func listing(of url: URL) -> Workspace.Listing? {
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
        pendingDelete = nil

        // Opening is idempotent, and it no longer closes anything: the
        // worktree being left stays open and keeps its listings, so coming back
        // to it costs nothing and shows what it showed.
        let state = if let key { await store.open(WorkspaceID(key)) } else { nil as Workspace? }
        // Weak, or the state would hold this model which holds the store which
        // holds the state.
        registration = state?.observe(onChange: { [weak self] in self?.dropWhatHasGone() })
        // Held before the first read, so the folders show as they are read
        // rather than all at once once git has answered as well.
        worktree = state
        await readRestoredFolders()
        await state?.refresh()
    }

    /// Reads the folders restored as open, which nothing has read yet after a
    /// launch: without a listing a folder draws open with nothing in it, and
    /// the first click closes it instead of showing it.
    ///
    /// Parents before children, so a folder is looked for in a listing that is
    /// already there. One that is gone (deleted or renamed since the last
    /// session) is skipped rather than read, or it would be cached as
    /// unreadable.
    private func readRestoredFolders() async {
        guard let worktree else { return }
        await worktree.open(worktree.root)
        for folder in expanded.sorted() where worktree.exists(folder) == true {
            await worktree.open(folder)
        }
    }

    /// Whether the app is in front. Suspends drains for every workspace while
    /// it is not: changes keep accumulating and are acted on in one go when it
    /// comes back, because the worst storms happen while the user is in a
    /// terminal running the build that causes them.
    func setWatching(_ enabled: Bool) {
        store.setFrontmost(enabled)
    }

    func isExpanded(_ folder: URL) -> Bool {
        expanded.contains(Self.key(folder))
    }

    func toggle(_ folder: URL) async {
        let key = Self.key(folder)
        if expanded.remove(key) == nil {
            expanded.insert(key)
            await worktree?.open(key)
        }
    }

    /// `nil` clears the highlight, which is what the editor showing nothing
    /// means.
    public func select(_ file: URL?) {
        selected = file
    }

    func beginRenaming(_ url: URL) {
        creating = nil
        renaming = url
    }

    /// Opens a name field inside `folder`, opening the folder if it is closed.
    /// Nothing is made until the name is committed.
    func beginCreating(in folder: URL, isDirectory: Bool) async {
        guard let worktree else { return }
        let key = Self.key(folder)
        renaming = nil
        if key != worktree.root { expanded.insert(key) }
        // Before the read, so the field appears as the listing does and not
        // after git has answered as well.
        creating = Creation(parent: key, isDirectory: isDirectory)
        await worktree.open(key)
    }

    func cancelCreating() {
        creating = nil
    }

    /// Makes what the name field describes and shows it. A blank or unusable
    /// name, or a refusal from the disk (the name is taken, say), makes
    /// nothing. A new file is selected; a new folder is left closed.
    func commitCreating(named name: String) async {
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

    func cancelRenaming() {
        renaming = nil
    }

    /// Renames `entry` on disk, then re-reads so the tree shows the result. A
    /// blank, unchanged or unusable name, or a refusal from the disk (the name
    /// is taken, say), leaves everything as it was.
    func commitRename(_ entry: DirectoryEntry, to name: String) async {
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

    /// Moves `entry` to the Trash at once, or, to delete it for good, asks first
    /// by holding it in ``pendingDelete``.
    func requestDelete(_ entry: DirectoryEntry, permanently: Bool) async {
        if permanently {
            pendingDelete = entry
        } else {
            await delete(entry, permanently: false)
        }
    }

    /// Deletes what ``pendingDelete`` asked about. Takes the entry rather than
    /// reading it, because the alert dismissing clears the request.
    func confirmDelete(_ entry: DirectoryEntry) async {
        pendingDelete = nil
        await delete(entry, permanently: true)
    }

    func cancelDelete() {
        pendingDelete = nil
    }

    /// A refusal from the disk leaves everything as it was, and the refresh
    /// shows the item still there.
    private func delete(_ entry: DirectoryEntry, permanently: Bool) async {
        guard let worktree else { return }
        let gone = Self.key(entry.url)
        if let renaming, Self.key(renaming).isInside(gone) { self.renaming = nil }

        do {
            try await worktree.delete(entry.url, permanently: permanently)
        } catch {
            return
        }
        // The selection is left to ``dropWhatHasGone()``, which clears the
        // highlight with the row. Nothing else is selected in its place, and the
        // editor keeps the tab, struck through.
        expanded = expanded.filter { !$0.isInside(gone) }
    }

    /// Closes every folder below the root.
    func collapseAll() {
        expanded = []
    }

    /// Re-reads the root and every open folder, then asks git about the tree.
    func refresh() async {
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

    private func rows(in folder: PathKey, depth: Int, underIgnored: Bool = false) -> [FileTreeRow] {
        guard let worktree else { return [] }
        let parent = folder.url

        switch worktree.listing(of: folder) {
        case .loaded(let entries):
            let field = creating.flatMap { $0.parent == folder ? $0 : nil }
                .map {
                    FileTreeRow(kind: .creating(isDirectory: $0.isDirectory), depth: depth, parent: parent, creation: $0.id)
                }
            var result: [FileTreeRow] = []
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
                var row = FileTreeRow(kind: .entry(entry), depth: depth, parent: parent)
                row.isIgnored = isIgnored
                if !isIgnored {
                    row.tint = tint(of: key, isDirectory: entry.isDirectory)
                    row.mark = isOpen ? nil : row.tint
                }
                result.append(row)
                if isOpen {
                    result += rows(in: key, depth: depth + 1, underIgnored: isIgnored)
                }
            }
            if !placed, let field { result.append(field) }
            return result
        case .unreadable:
            return [FileTreeRow(kind: .unreadable, depth: depth, parent: parent)]
        case nil:
            return []
        }
    }

    /// A file wears what git says about it. A folder wears what changed inside
    /// it, or, when nothing did, what git says about the folder itself: a new
    /// folder is reported as one untracked entry and is not its own parent.
    ///
    /// The row shows this as a letter only while a folder is closed: once it is
    /// open, the rows inside say it better than a letter on the folder could.
    private func tint(of path: PathKey, isDirectory: Bool) -> GitMark? {
        guard let worktree else { return nil }
        let own = worktree.status.status(of: path).flatMap(GitMark.init)
        guard isDirectory else { return own }
        return worktree.status.rollup(of: path) ?? own
    }
}
