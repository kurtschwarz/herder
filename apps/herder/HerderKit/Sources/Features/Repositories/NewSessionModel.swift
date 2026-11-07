import Core
import Foundation
import Observation

/// The new-session modal's state: which worktree the session is for, and, for a
/// new one, the branch it is cut as and from.
///
/// Submitting either creates the worktree or takes the existing one, and says
/// where the session should start. Starting it is not this model's business:
/// it knows about git, not about agents.
@Observable
final class NewSessionModel {
    enum Choice: Equatable {
        case newWorktree
        case existing(GitWorktree.ID)
    }

    /// Why the typed branch name cannot be used.
    enum NameProblem: Equatable {
        case invalid(String)
        case alreadyExists
    }

    private let git: any GitClient
    private let repository: URL

    let repositoryName: String

    private(set) var worktrees: [GitWorktree] = []
    private(set) var branches: [String] = []
    private(set) var isLoading = true
    private(set) var isCreating = false

    /// What went wrong reading the repository or creating the worktree, in
    /// git's own words where git had some.
    private(set) var failure: String?

    private(set) var choice: Choice = .newWorktree
    private(set) var branchName = ""
    var baseBranch = ""
    var filter = ""

    private var kind: GitRepositoryKind = .notARepository

    init(repositoryName: String, repository: URL, git: any GitClient) {
        self.repositoryName = repositoryName
        self.repository = repository
        self.git = git
    }

    // MARK: - Loading

    /// Reads the worktrees and branches the lists are made of. A repository
    /// that cannot be read leaves them empty and says so in `failure`.
    func load() async {
        defer { isLoading = false }

        do {
            kind = try await git.repositoryKind(at: repository)
            worktrees = try await git.worktrees(at: repository)
            branches = try await git.branches(at: repository)
        } catch {
            failure = "Couldn't read this repository."
            return
        }

        if baseBranch.isEmpty { baseBranch = defaultBase() }
    }

    /// Where a new branch most likely starts: what the main working tree has
    /// checked out, then the conventional names, then whatever comes first.
    private func defaultBase() -> String {
        if let main = worktrees.first(where: \.isMainWorkingTree),
           case .branch(let name) = main.checkout, branches.contains(name) {
            return name
        }
        return ["main", "master"].first(where: branches.contains) ?? branches.first ?? ""
    }

    // MARK: - Choosing

    func selectNewWorktree() {
        choice = .newWorktree
    }

    func select(_ worktree: GitWorktree) {
        choice = .existing(worktree.id)
    }

    /// Typing a branch name means the new worktree is the one wanted.
    func editBranchName(_ name: String) {
        branchName = name
        choice = .newWorktree
        failure = nil
    }

    var filteredWorktrees: [GitWorktree] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return worktrees }
        return worktrees.filter { Self.label(of: $0).localizedCaseInsensitiveContains(query) }
    }

    static func label(of worktree: GitWorktree) -> String {
        switch worktree.checkout {
        case .branch(let name): name
        case .detached(let sha): sha
        }
    }

    // MARK: - Creating

    /// The worktree chosen from the list, if one is.
    var selectedWorktree: GitWorktree? {
        guard case .existing(let id) = choice else { return nil }
        return worktrees.first { $0.id == id }
    }

    /// Whether there is something to submit: a name that will do for a new
    /// worktree, or an existing worktree to open.
    var canSubmit: Bool {
        selectedWorktree != nil ? !isLoading && !isCreating : canCreate
    }

    /// Makes the worktree if a new one is wanted, and says where the session
    /// goes. `nil` when it could not be made, with `failure` saying why.
    func submit() async -> URL? {
        if let worktree = selectedWorktree {
            guard canSubmit else { return nil }
            return worktree.path
        }
        guard await create(), let location else { return nil }
        return location
    }

    /// `nil` for an empty name: nothing to complain about yet.
    var nameProblem: NameProblem? {
        switch GitRefName.problem(in: branchName) {
        case .empty: nil
        case .invalid(let reason): .invalid(reason)
        case nil: branches.contains(branchName) ? .alreadyExists : nil
        }
    }

    var canCreate: Bool {
        choice == .newWorktree
            && !branchName.isEmpty
            && nameProblem == nil
            && !baseBranch.isEmpty
            && location != nil
            && !isLoading
            && !isCreating
    }

    /// Where the worktree would go, shown so nobody is surprised by it.
    var location: URL? {
        GitWorktreeLocation.path(forBranch: branchName, inRepository: repository, kind: kind)
    }

    /// Creates the worktree. Returns whether it was created; on `false`,
    /// `failure` says why.
    func create() async -> Bool {
        guard canCreate, let location else { return false }
        isCreating = true
        defer { isCreating = false }

        do {
            try await git.addWorktree(in: repository, at: location, newBranch: branchName, from: baseBranch)
            return true
        } catch GitClientError.commandFailed(let message) {
            failure = message
        } catch {
            failure = error.localizedDescription
        }
        return false
    }
}
