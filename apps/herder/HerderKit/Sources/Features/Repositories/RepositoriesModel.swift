import Core
import Foundation
import Observation

/// Everything about the repository list that is not the list itself.
///
/// The list itself comes from ``WindowRepositories``, which this never caches:
/// the repositories this window lists, in its order, and which are on show.
/// What this holds is derived or ephemeral: each repository's worktrees as last
/// read, and which one is being renamed.
///
/// The sidebar does not list repositories or worktrees as rows: it lists the
/// sessions in those on show, each labelled with its worktree, and the
/// repositories themselves are picked, named and removed in the workspace
/// selector.
///
/// **Not** which worktree is active. That is the window's, in `WindowEnvironment`,
/// because two windows can show different checkouts and a model held once per
/// app cannot answer for both.
@Observable
public final class RepositoriesModel {
    /// What reading a repository's worktrees came to. A failed read is its own
    /// state because an empty list would claim the repository has none.
    enum Listing: Equatable {
        case loaded([GitWorktree])
        case unreadable
    }

    private let list: WindowRepositories
    private let git: any GitClient
    private let picker: any FolderPickerClient

    private(set) var listings: [UUID: Listing] = [:]

    /// Where a repository's session history is kept, and the worktrees it has
    /// now, which is how a session whose worktree has gone is known.
    struct HistorySource: Equatable {
        var name: String
        var key: PathKey
        var worktrees: Set<WorkspaceID>
    }

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
        repositories: WindowRepositories,
        git: any GitClient,
        picker: any FolderPickerClient
    ) {
        self.list = repositories
        self.git = git
        self.picker = picker
    }

    /// The repositories this window lists, in its order.
    var repositories: [Repository] { list.repositories }

    /// The ones the workspace selector has left on the sidebar.
    var shownRepositories: [Repository] { list.shown }

    func isShown(_ repository: Repository) -> Bool {
        list.isShown(repository)
    }

    /// Whether unticking this one in the selector would do anything. The last
    /// one showing stays, so the sidebar is never empty while it lists any.
    func canHide(_ repository: Repository) -> Bool {
        list.shown.map(\.id) != [repository.id]
    }

    func setShown(_ repository: Repository, _ isShown: Bool) {
        list.setShown(repository, isShown)
    }

    func showAll() {
        list.showAll()
    }

    /// What the selector's button says: the one name when one is showing.
    var selectionTitle: String {
        let shown = shownRepositories
        switch shown.count {
        case 0: return "Workspaces"
        case 1: return shown[0].name
        case repositories.count: return "All workspaces"
        default: return "\(shown.count) workspaces"
        }
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
            return list.repository(id: id)?.name
        }
        return nil
    }

    public func beginAdding() {
        guard !isModalPresented else { return }
        adding = AddRepositoryModel(repositories: list, picker: picker)
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

    /// Makes the worktree the modal describes, if it is a new one, closes it,
    /// and shows the worktree under its repository. Returns the worktree the
    /// session is for. A failure leaves the modal up with the reason.
    func submitNewSession() async -> WorkspaceID? {
        guard let newSession, let path = await newSession.submit() else { return nil }
        let repository = newSessionRepository
        cancelNewSession()
        if let repository { await refresh(repository) }
        return WorkspaceID(path)
    }

    /// Re-reads the worktrees of every repository given, which is the ones on
    /// show. An unavailable one costs nothing: there is nothing to read.
    func refresh(_ repositories: [Repository]) async {
        for repository in repositories {
            await refresh(repository)
        }
    }

    func refresh(_ repository: Repository) async {
        guard repository.isAvailable else { return }
        let id = repository.id

        do {
            let worktrees = try await git.worktrees(at: URL(filePath: repository.path))
            listings[id] = .loaded(worktrees)
        } catch {
            // The task that asked was cancelled, which says nothing about the
            // folder.
            guard !Task.isCancelled else { return }
            listings[id] = .unreadable
        }
    }

    func commitRename(_ repository: Repository, to name: String) async {
        renaming = nil
        await list.rename(repository, to: name)
    }

    /// Takes the repository out of this window. Others listing it keep it, and
    /// so does the pool: see ``WindowRepositories/remove(_:)``.
    func remove(_ repository: Repository) {
        list.remove(repository)
        listings[repository.id] = nil
    }

    // MARK: - Sessions

    /// What a session in each worktree of `repositories` is labelled with:
    /// its branch, and its repository's name in front when there is more than
    /// one to tell apart. A worktree not in here belongs to none of them.
    func worktreeLabels(of repositories: [Repository]) -> [WorkspaceID: String] {
        var labels: [WorkspaceID: String] = [:]
        for repository in repositories {
            guard case .loaded(let worktrees)? = listings[repository.id] else { continue }
            for worktree in worktrees {
                let branch = NewSessionModel.label(of: worktree)
                labels[WorkspaceID(worktree.path)] = repositories.count > 1 ? "\(repository.name)/\(branch)" : branch
            }
        }
        return labels
    }

    /// Where the history of each of `repositories` is kept, and the worktrees
    /// it has now. One whose worktrees have not been read is keyed by its own
    /// folder, which is its main working tree unless it is bare, and has no
    /// worktree its sessions could be resumed in.
    func historySources(of repositories: [Repository]) -> [HistorySource] {
        repositories.filter(\.isAvailable).map { repository in
            let worktrees = if case .loaded(let listed)? = listings[repository.id] { listed } else { [GitWorktree]() }
            return HistorySource(
                name: repository.name,
                key: SessionHistory.repositoryKey(for: worktrees, fallback: PathKey(repository.url)),
                worktrees: Set(worktrees.map { WorkspaceID($0.path) })
            )
        }
    }
}
