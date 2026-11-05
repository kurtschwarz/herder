import Core
import Foundation
import Observation
import Storage

/// Everything about the workspace list that is not the list itself.
///
/// The workspaces come from `@Query`, so this never caches them. What it holds
/// is derived or ephemeral: each workspace's worktrees as last read, which
/// workspaces the user has folded away, and which row is being renamed.
///
/// **Not** which worktree is active. That is the window's, in `WindowModel`,
/// because two windows can show different checkouts and a model held once per
/// app cannot answer for both. Rows learn whether they are the active one from
/// the `Workspace` in the environment, and ask for a change through
/// ``OpenWorkspaceAction``.
@Observable
public final class WorkspacesModel {
    /// What reading a workspace's worktrees came to. A failed read is its own
    /// state because an empty list would claim the repository has none.
    public enum Listing: Equatable {
        case loaded([GitWorktree])
        case unreadable
    }

    private static let collapsedKey = "collapsedWorkspaces"

    private let store: SwiftDataRepositoryStore
    private let git: any GitClient
    private let picker: any FolderPickerClient
    private let defaults: UserDefaults

    public private(set) var listings: [UUID: Listing] = [:]

    /// Folded workspaces rather than unfolded ones, so a workspace the user has
    /// never touched, and one added later, starts open.
    public private(set) var collapsed: Set<UUID>

    /// Each workspace's name, as last read. Kept beside ``listings`` so that
    /// naming the workspace a worktree belongs to costs no fetch: a view asks
    /// for it on every redraw, and the old code cached a whole record to avoid
    /// exactly that.
    private var names: [UUID: String] = [:]

    /// The workspace whose name is being edited in place.
    public var renaming: UUID?

    /// The add-workspace modal's state while it is up, `nil` otherwise.
    public private(set) var adding: AddWorkspaceModel?

    /// The new-session modal's state while it is up, `nil` otherwise.
    public private(set) var newSession: NewSessionModel?

    /// The workspace the new-session modal is open for, so its worktrees can be
    /// re-read once one is created.
    private var newSessionWorkspace: Repository?

    /// Whether a modal is covering the window.
    public var isModalPresented: Bool { adding != nil || newSession != nil }

    public init(
        store: SwiftDataRepositoryStore,
        git: any GitClient,
        picker: any FolderPickerClient,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.git = git
        self.picker = picker
        self.defaults = defaults
        let saved = defaults.stringArray(forKey: Self.collapsedKey) ?? []
        self.collapsed = Set(saved.compactMap(UUID.init(uuidString:)))
    }

    /// What the workspace holding the worktree at `path` is called.
    ///
    /// For a pane that wants to say what it is showing: a worktree's own folder
    /// is often `main`, which says nothing about what it belongs to. `nil` when
    /// no workspace on show claims it.
    ///
    /// Derived rather than remembered. The association used to be a stored
    /// `selectedWorkspace` kept in step with the selection by hand; the
    /// listings already know which workspace each worktree came from.
    public func nameOfWorkspace(holding path: URL) -> String? {
        let key = PathKey(path)
        for (id, listing) in listings {
            guard case .loaded(let worktrees) = listing else { continue }
            guard worktrees.contains(where: { PathKey($0.path) == key }) else { continue }
            return names[id]
        }
        return nil
    }

    /// Whether the worktree at `path` is one this list is showing. Used to stop
    /// a window holding on to a worktree that has been removed in a terminal.
    public func isKnown(_ path: URL) -> Bool {
        nameOfWorkspace(holding: path) != nil
    }

    public func beginAdding() {
        guard !isModalPresented else { return }
        adding = AddWorkspaceModel(store: store, picker: picker)
    }

    public func cancelAdding() {
        adding = nil
    }

    /// Adds the folder the modal has validated and closes it. A refusal at this
    /// point leaves the modal up, showing why.
    public func submitAdding() async {
        guard let adding, await adding.submit() else { return }
        self.adding = nil
    }

    public func beginNewSession(in workspace: Repository) {
        guard !isModalPresented, workspace.isAvailable else { return }
        newSessionWorkspace = workspace
        newSession = NewSessionModel(
            workspaceName: workspace.name,
            repository: URL(filePath: workspace.path),
            git: git
        )
    }

    public func cancelNewSession() {
        newSession = nil
        newSessionWorkspace = nil
    }

    /// Creates the worktree the modal describes, closes it, and shows the new
    /// worktree under its workspace. A failure leaves the modal up with the
    /// reason.
    public func submitNewSession() async {
        guard let newSession, await newSession.create() else { return }
        let workspace = newSessionWorkspace
        cancelNewSession()
        if let workspace { await refresh(workspace) }
    }

    public func isExpanded(_ workspace: Repository) -> Bool {
        workspace.isAvailable && !collapsed.contains(workspace.id)
    }

    public func toggle(_ workspace: Repository) async {
        if collapsed.remove(workspace.id) == nil {
            collapsed.insert(workspace.id)
        }
        persistCollapsed()
        await refresh(workspace)
    }

    /// Re-reads the worktrees of every workspace that is showing them. A
    /// collapsed or unavailable workspace costs nothing: nobody is looking.
    public func refresh(_ workspaces: [Repository]) async {
        for workspace in workspaces {
            await refresh(workspace)
        }
    }

    public func refresh(_ workspace: Repository) async {
        guard isExpanded(workspace) else { return }
        let id = workspace.id

        do {
            let worktrees = try await git.worktrees(at: URL(filePath: workspace.path))
            listings[id] = .loaded(worktrees)
            names[id] = workspace.name
        } catch {
            // The task that asked was cancelled, which says nothing about the
            // folder.
            guard !Task.isCancelled else { return }
            listings[id] = .unreadable
        }
    }

    public func commitRename(_ workspace: Repository, to name: String) {
        renaming = nil
        do {
            try store.rename(workspace, to: name)
            names[workspace.id] = workspace.name
        } catch {
            assertionFailure("Could not rename workspace: \(error)")
        }
    }

    public func remove(_ workspace: Repository) {
        let id = workspace.id
        do {
            try store.delete(workspace)
        } catch {
            assertionFailure("Could not remove workspace: \(error)")
            return
        }
        listings[id] = nil
        names[id] = nil
        if collapsed.remove(id) != nil { persistCollapsed() }
    }

    private func persistCollapsed() {
        defaults.set(collapsed.map(\.uuidString).sorted(), forKey: Self.collapsedKey)
    }
}
