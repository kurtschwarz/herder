import Core
import Foundation
import Observation

/// Everything about the repository list that is not the list itself.
///
/// The list itself comes from ``RepositoryStore``, which this never caches.
/// What it holds is derived or ephemeral: each repository's worktrees as last
/// read, which repositories the user has folded away, and which row is being
/// renamed.
///
/// **Not** which worktree is active. That is the window's, in `WindowModel`,
/// because two windows can show different checkouts and a model held once per
/// app cannot answer for both. Rows learn whether they are the active one from
/// the `Workspace` in the environment, and ask for a change through
/// ``OpenWorkspaceAction``.
@Observable
public final class RepositoriesModel {
    /// What reading a repository's worktrees came to. A failed read is its own
    /// state because an empty list would claim the repository has none.
    enum Listing: Equatable {
        case loaded([GitWorktree])
        case unreadable
    }

    private let store: RepositoryStore
    private let git: any GitClient
    private let picker: any FolderPickerClient

    private(set) var listings: [UUID: Listing] = [:]

    /// Each repository's name, as last read. Kept beside ``listings`` so that
    /// naming the repository a worktree belongs to costs no fetch: a view asks
    /// for it on every redraw, and the old code cached a whole record to avoid
    /// exactly that.
    private var names: [UUID: String] = [:]

    /// The repository whose name is being edited in place.
    var renaming: UUID?

    /// The add-repository modal's state while it is up, `nil` otherwise.
    private(set) var adding: AddRepositoryModel?

    /// The new-session modal's state while it is up, `nil` otherwise.
    private(set) var newSession: NewSessionModel?

    /// The repository the new-session modal is open for, so its worktrees can be
    /// re-read once one is created.
    private var newSessionRepository: Repository?

    /// Whether a modal is covering the window.
    public var isModalPresented: Bool { adding != nil || newSession != nil }

    public init(
        store: RepositoryStore,
        git: any GitClient,
        picker: any FolderPickerClient
    ) {
        self.store = store
        self.git = git
        self.picker = picker
    }

    /// What the repository holding the worktree at `path` is called.
    ///
    /// For a pane that wants to say what it is showing: a worktree's own folder
    /// is often `main`, which says nothing about what it belongs to. `nil` when
    /// no repository on show claims it.
    ///
    /// Derived rather than remembered. The association used to be a stored
    /// `selectedWorkspace` kept in step with the selection by hand; the
    /// listings already know which repository each worktree came from.
    public func nameOfRepository(holding path: URL) -> String? {
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
    func isKnown(_ path: URL) -> Bool {
        nameOfRepository(holding: path) != nil
    }

    public func beginAdding() {
        guard !isModalPresented else { return }
        adding = AddRepositoryModel(store: store, picker: picker)
    }

    func cancelAdding() {
        adding = nil
    }

    /// Adds the folder the modal has validated and closes it. A refusal at this
    /// point leaves the modal up, showing why.
    func submitAdding() async {
        guard let adding, await adding.submit() else { return }
        self.adding = nil
    }

    func beginNewSession(in repository: Repository) {
        guard !isModalPresented, repository.isAvailable else { return }
        newSessionRepository = repository
        newSession = NewSessionModel(
            repositoryName: repository.name,
            repository: URL(filePath: repository.path),
            git: git
        )
    }

    func cancelNewSession() {
        newSession = nil
        newSessionRepository = nil
    }

    /// Creates the worktree the modal describes, closes it, and shows the new
    /// worktree under its repository. A failure leaves the modal up with the
    /// reason.
    func submitNewSession() async {
        guard let newSession, await newSession.create() else { return }
        let repository = newSessionRepository
        cancelNewSession()
        if let repository { await refresh(repository) }
    }

    func isExpanded(_ repository: Repository) -> Bool {
        // Read off the store, not off the copy the caller is holding: the row
        // is the one place that knows, and it is what gets persisted.
        repository.isAvailable && !(store[repository.id]?.isCollapsed ?? repository.isCollapsed)
    }

    func toggle(_ repository: Repository) async {
        // Showing becomes folding, and folding becomes showing.
        await store.setCollapsed(repository, isExpanded(repository))
        await refresh(repository)
    }

    /// Re-reads the worktrees of every repository that is showing them. A
    /// collapsed or unavailable repository costs nothing: nobody is looking.
    func refresh(_ repositories: [Repository]) async {
        for repository in repositories {
            await refresh(repository)
        }
    }

    func refresh(_ repository: Repository) async {
        guard isExpanded(repository) else { return }
        let id = repository.id

        do {
            let worktrees = try await git.worktrees(at: URL(filePath: repository.path))
            listings[id] = .loaded(worktrees)
            names[id] = repository.name
        } catch {
            // The task that asked was cancelled, which says nothing about the
            // folder.
            guard !Task.isCancelled else { return }
            listings[id] = .unreadable
        }
    }

    func commitRename(_ repository: Repository, to name: String) async {
        renaming = nil
        await store.rename(repository, to: name)
        names[repository.id] = store[repository.id]?.name ?? repository.name
    }

    func remove(_ repository: Repository) async {
        let id = repository.id
        await store.delete(repository)
        listings[id] = nil
        names[id] = nil
    }
}
