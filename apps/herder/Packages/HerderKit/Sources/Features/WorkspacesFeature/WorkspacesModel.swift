import Clients
import Foundation
import Observation
import Storage

/// Everything about the workspace list that is not the list itself.
///
/// The workspaces come from `@Query`, so this never caches them. What it holds
/// is derived or ephemeral: each workspace's worktrees as last read, which
/// workspaces the user has folded away, and which row is being renamed.
@Observable
public final class WorkspacesModel {
    /// What reading a workspace's worktrees came to. A failed read is its own
    /// state because an empty list would claim the repository has none.
    public enum Listing: Equatable {
        case loaded([GitWorktree])
        case unreadable
    }

    private static let collapsedKey = "collapsedWorkspaces"
    private static let selectedPathKey = "selectedWorktreePath"
    private static let selectedWorkspaceKey = "selectedWorktreeWorkspace"

    private let store: WorkspaceStore
    private let git: any GitClient
    private let picker: any FolderPickerClient
    private let defaults: UserDefaults

    public private(set) var listings: [UUID: Listing] = [:]

    /// Folded workspaces rather than unfolded ones, so a workspace the user has
    /// never touched, and one added later, starts open.
    public private(set) var collapsed: Set<UUID>

    /// The worktree the user last clicked, whose files the explorer shows.
    /// Cleared when a read finds it gone.
    public private(set) var selectedWorktree: URL?

    /// The workspace `selectedWorktree` was picked under, so that workspace's
    /// listing is the one that can say it has gone.
    private var selectedWorkspace: UUID?

    /// The workspace whose name is being edited in place.
    public var renaming: UUID?

    /// The add-workspace modal's state while it is up, `nil` otherwise.
    public private(set) var adding: AddWorkspaceModel?

    /// The new-session modal's state while it is up, `nil` otherwise.
    public private(set) var newSession: NewSessionModel?

    /// The workspace the new-session modal is open for, so its worktrees can be
    /// re-read once one is created.
    private var newSessionWorkspace: Workspace?

    /// Whether a modal is covering the window.
    public var isModalPresented: Bool { adding != nil || newSession != nil }

    public init(
        store: WorkspaceStore,
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
        if let path = defaults.string(forKey: Self.selectedPathKey),
           let workspace = defaults.string(forKey: Self.selectedWorkspaceKey).flatMap(UUID.init(uuidString:)) {
            self.selectedWorktree = URL(filePath: path)
            self.selectedWorkspace = workspace
        }
    }

    /// Selecting what is already selected changes nothing.
    public func select(_ worktree: GitWorktree, in workspace: Workspace) {
        guard worktree.path != selectedWorktree else { return }
        setSelection(worktree.path, in: workspace.id)
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

    public func beginNewSession(in workspace: Workspace) {
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

    public func isExpanded(_ workspace: Workspace) -> Bool {
        workspace.isAvailable && !collapsed.contains(workspace.id)
    }

    public func toggle(_ workspace: Workspace) async {
        if collapsed.remove(workspace.id) == nil {
            collapsed.insert(workspace.id)
        }
        persistCollapsed()
        await refresh(workspace)
    }

    /// Re-reads the worktrees of every workspace that is showing them. A
    /// collapsed or unavailable workspace costs nothing: nobody is looking.
    public func refresh(_ workspaces: [Workspace]) async {
        for workspace in workspaces {
            await refresh(workspace)
        }
    }

    public func refresh(_ workspace: Workspace) async {
        guard isExpanded(workspace) else { return }
        let id = workspace.id

        do {
            let worktrees = try await git.worktrees(at: URL(filePath: workspace.path))
            listings[id] = .loaded(worktrees)
            if selectedWorkspace == id, let selectedWorktree, !worktrees.contains(where: { $0.path == selectedWorktree }) {
                setSelection(nil, in: nil)
            }
        } catch {
            // The task that asked was cancelled, which says nothing about the
            // folder.
            guard !Task.isCancelled else { return }
            listings[id] = .unreadable
        }
    }

    public func commitRename(_ workspace: Workspace, to name: String) {
        renaming = nil
        do {
            try store.rename(workspace, to: name)
        } catch {
            assertionFailure("Could not rename workspace: \(error)")
        }
    }

    public func remove(_ workspace: Workspace) {
        let id = workspace.id
        do {
            try store.delete(workspace)
        } catch {
            assertionFailure("Could not remove workspace: \(error)")
            return
        }
        listings[id] = nil
        if selectedWorkspace == id { setSelection(nil, in: nil) }
        if collapsed.remove(id) != nil { persistCollapsed() }
    }

    private func setSelection(_ worktree: URL?, in workspace: UUID?) {
        selectedWorktree = worktree
        selectedWorkspace = workspace
        defaults.set(worktree?.path(percentEncoded: false), forKey: Self.selectedPathKey)
        defaults.set(workspace?.uuidString, forKey: Self.selectedWorkspaceKey)
    }

    private func persistCollapsed() {
        defaults.set(collapsed.map(\.uuidString).sorted(), forKey: Self.collapsedKey)
    }
}
