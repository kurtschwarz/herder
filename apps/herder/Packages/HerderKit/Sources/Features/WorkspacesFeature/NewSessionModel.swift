import Core
import Foundation
import Observation

/// The new-session modal's state: which worktree the session is for, and, for a
/// new one, the branch it is cut as and from.
///
/// Only creating a worktree does anything yet. Opening a session in an existing
/// worktree waits for a session runtime, so that choice can be made but not
/// submitted.
@Observable
public final class NewSessionModel {
    public enum Choice: Equatable {
        case newWorktree
        case existing(GitWorktree.ID)
    }

    /// Why the typed branch name cannot be used.
    public enum NameProblem: Equatable {
        case invalid(String)
        case alreadyExists
    }

    private let git: any GitClient
    private let repository: URL

    public let workspaceName: String

    public private(set) var worktrees: [GitWorktree] = []
    public private(set) var branches: [String] = []
    public private(set) var isLoading = true
    public private(set) var isCreating = false

    /// What went wrong reading the repository or creating the worktree, in
    /// git's own words where git had some.
    public private(set) var failure: String?

    public private(set) var choice: Choice = .newWorktree
    public private(set) var branchName = ""
    public var baseBranch = ""
    public var filter = ""

    private var kind: GitRepositoryKind = .notARepository

    public init(workspaceName: String, repository: URL, git: any GitClient) {
        self.workspaceName = workspaceName
        self.repository = repository
        self.git = git
    }

    // MARK: - Loading

    /// Reads the worktrees and branches the lists are made of. A repository
    /// that cannot be read leaves them empty and says so in `failure`.
    public func load() async {
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

    public func selectNewWorktree() {
        choice = .newWorktree
    }

    public func select(_ worktree: GitWorktree) {
        choice = .existing(worktree.id)
    }

    /// Typing a branch name means the new worktree is the one wanted.
    public func editBranchName(_ name: String) {
        branchName = name
        choice = .newWorktree
        failure = nil
    }

    public var filteredWorktrees: [GitWorktree] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return worktrees }
        return worktrees.filter { Self.label(of: $0).localizedCaseInsensitiveContains(query) }
    }

    public static func label(of worktree: GitWorktree) -> String {
        switch worktree.checkout {
        case .branch(let name): name
        case .detached(let sha): sha
        }
    }

    // MARK: - Creating

    /// `nil` for an empty name: nothing to complain about yet.
    public var nameProblem: NameProblem? {
        switch GitRefName.problem(in: branchName) {
        case .empty: nil
        case .invalid(let reason): .invalid(reason)
        case nil: branches.contains(branchName) ? .alreadyExists : nil
        }
    }

    public var canCreate: Bool {
        choice == .newWorktree
            && !branchName.isEmpty
            && nameProblem == nil
            && !baseBranch.isEmpty
            && location != nil
            && !isLoading
            && !isCreating
    }

    /// Where the worktree would go, shown so nobody is surprised by it.
    public var location: URL? {
        GitWorktreeLocation.path(forBranch: branchName, inRepository: repository, kind: kind)
    }

    /// Creates the worktree. Returns whether it was created; on `false`,
    /// `failure` says why.
    public func create() async -> Bool {
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
