import Core
import Foundation
import Observation

/// The New order card's state: what was typed, and turning it into a named
/// worktree.
///
/// Planning an order asks a model for a name while the remote's default branch
/// is fetched, builds the branch from the name, and cuts a worktree from that
/// default branch. Starting the agent in it is not this model's business: it
/// knows about git and names, not about agents.
///
/// Both slow steps may fail without stopping the order. A name that does not
/// come in time is a `chore/<adjective>-<noun>` branch, and a fetch that fails
/// is cut from the ref already there. The names are all decided before the
/// worktree exists, so nothing is renamed or moved afterwards.
@Observable
final class NewOrderModel {
    /// A worktree made for an order, and what its session starts with.
    struct Started: Equatable {
        var worktree: URL
        /// What the session is called in the sidebar.
        var title: String
        /// The typed text in the user's template, which is the agent's first
        /// message.
        var prompt: String
    }

    /// The longest a title taken from the prompt runs. About what a tab shows.
    static let maxTitleLength = 40

    private let git: any GitClient
    private let namer: any SessionNamer
    private let naming: () -> NamingConfiguration
    private let promptTemplate: () -> String
    private let namingTimeout: Duration

    /// What was typed. Only the input reads it, so typing redraws the input
    /// and not the card around it; the card reads ``hasText``.
    var text = "" {
        didSet { hasText = !prompt.isEmpty }
    }

    /// Whether there is anything but whitespace typed. Changes only when that
    /// flips, not on each key.
    private(set) var hasText = false

    private(set) var isWorking = false

    /// What went wrong making the worktree, in git's own words where git had
    /// some. Cleared by the next try.
    private(set) var failure: String?

    /// The workspace picked by hand, which the card stays on. `nil` follows
    /// the active one.
    private(set) var pickedRepository: UUID?

    /// Changes when the input should take the keyboard.
    private(set) var focusRequest = 0

    init(
        git: any GitClient,
        namer: any SessionNamer,
        naming: @escaping () -> NamingConfiguration,
        promptTemplate: @escaping () -> String = { "" },
        namingTimeout: Duration = .seconds(4)
    ) {
        self.git = git
        self.namer = namer
        self.naming = naming
        self.promptTemplate = promptTemplate
        self.namingTimeout = namingTimeout
    }

    var prompt: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canSubmit: Bool { hasText && !isWorking }

    func pick(_ repository: Repository?) {
        pickedRepository = repository?.id
    }

    func requestFocus() {
        focusRequest += 1
    }

    /// Makes the worktree for what was typed, and says where the session
    /// starts. Clears the text on success; on `nil` the text stays and
    /// `failure` says why.
    func submit(in repository: URL) async -> Started? {
        let prompt = prompt
        guard !prompt.isEmpty, !isWorking else { return nil }
        isWorking = true
        failure = nil
        defer { isWorking = false }

        async let name = name(for: prompt)
        async let fetched = fetchedBase(in: repository)
        let (sessionName, fetchedBase) = await (name, fetched)

        do {
            let kind = try await git.repositoryKind(at: repository)
            let branches = Set(try await git.branches(at: repository))

            let base = if let fetchedBase { fetchedBase } else { await Self.existingDefault(in: repository, git: git, branches: branches) }
            guard let base else {
                failure = "Couldn't find a default branch to start from."
                return nil
            }
            var generator = SystemRandomNumberGenerator()
            let branch = if let sessionName {
                OrderBranchName.make(
                    type: sessionName.type, slug: sessionName.slug, existing: branches, using: &generator
                )
            } else {
                OrderBranchName.fallback(existing: branches, using: &generator)
            }
            guard let location = GitWorktreeLocation.path(forBranch: branch, inRepository: repository, kind: kind)
            else {
                failure = "A worktree can't be made in this repository."
                return nil
            }

            try await git.addWorktree(in: repository, at: location, newBranch: branch, from: base)
            text = ""
            return Started(
                worktree: location,
                title: sessionName.map(\.title).flatMap(Self.nonBlank).map { String($0.prefix(Self.maxTitleLength)) }
                    ?? Self.title(from: prompt),
                prompt: FirstPromptTemplate.apply(promptTemplate(), to: prompt)
            )
        } catch GitClientError.commandFailed(let message) {
            failure = message
        } catch {
            failure = error.localizedDescription
        }
        return nil
    }

    // MARK: - The two slow steps

    /// What the naming call says, or `nil` when it fails or is not back in
    /// time, which is not worth telling anyone.
    private func name(for prompt: String) async -> SessionName? {
        let namer = namer
        let configuration = naming()
        let timeout = namingTimeout
        return await withTaskGroup(of: SessionName?.self) { group in
            group.addTask { try? await namer.name(for: prompt, using: configuration) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// The ref to cut from once the default branch is fetched. `nil` when the
    /// fetch could not be asked for, and the local branches have to do.
    private func fetchedBase(in repository: URL) async -> String? {
        (try? await git.fetchDefaultBranch(in: repository)) ?? nil
    }

    // MARK: - Names

    /// The default branch as it already is, for when the fetch could not be
    /// asked for: the remote-tracking `origin/main` or `origin/master` if
    /// there is one, else the local branch of that name.
    private static func existingDefault(in repository: URL, git: any GitClient, branches: Set<String>) async -> String? {
        let remote = Set(((try? await git.refs(in: repository)) ?? []).filter { $0.kind == .remoteBranch }.map(\.name))
        let names = ["main", "master"]
        return names.map { "origin/\($0)" }.first(where: remote.contains) ?? names.first(where: branches.contains)
    }

    private static func nonBlank(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The start of the prompt, for a session whose name did not come: its
    /// first line, cut to what a tab shows.
    static func title(from prompt: String) -> String {
        let line = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
        return String(line.trimmingCharacters(in: .whitespaces).prefix(maxTitleLength))
    }
}
