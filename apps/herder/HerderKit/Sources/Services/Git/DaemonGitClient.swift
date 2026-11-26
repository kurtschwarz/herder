import Core
import Foundation

/// `GitClient` that asks herderd, bound to the one host it runs on. See ADR 0002.
///
/// Every call goes to the daemon, and there is no fallback to running git here:
/// when the daemon is unreachable after the connect-or-spawn retry, a call
/// throws `GitClientError.commandFailed("herderd is not running")`.
public struct DaemonGitClient: GitClient {
    private let daemon: any DaemonClient
    private let nextID = RequestCounter()

    public init(daemon: any DaemonClient) {
        self.daemon = daemon
    }

    public func repositoryKind(at url: URL) async throws -> GitRepositoryKind {
        let result = try await ask("repository_kind", ["path": url.path(percentEncoded: false)])
        guard let kind = DaemonWire.repositoryKind(fromResult: result) else {
            throw Self.unrecognised
        }
        return kind
    }

    public func worktrees(at url: URL) async throws -> [GitWorktree] {
        let result = try await ask("worktrees", ["path": url.path(percentEncoded: false)])
        guard let worktrees = DaemonWire.worktrees(fromResult: result) else { throw Self.unrecognised }
        return worktrees
    }

    public func branches(at url: URL) async throws -> [String] {
        let result = try await ask("branches", ["path": url.path(percentEncoded: false)])
        guard let branches = DaemonWire.branches(fromResult: result) else { throw Self.unrecognised }
        return branches
    }

    public func gitDirectory(of url: URL) async throws -> URL? {
        let result = try await ask("git_directory", ["path": url.path(percentEncoded: false)])
        guard let directory = DaemonWire.gitDirectory(fromResult: result) else { throw Self.unrecognised }
        return directory
    }

    public func checkout(of url: URL) async throws -> GitWorktree.Checkout? {
        let result = try await ask("checkout", ["path": url.path(percentEncoded: false)])
        guard let checkout = DaemonWire.checkout(fromResult: result) else { throw Self.unrecognised }
        return checkout
    }

    public func status(in worktree: URL) async throws -> GitWorktreeStatus {
        let root = PathKey(worktree)
        let result = try await ask("status", ["path": root.path])
        guard let status = DaemonWire.status(fromResult: result, root: root) else { throw Self.unrecognised }
        return status
    }

    public func changeSummary(in worktree: URL) async throws -> GitChangeSummary? {
        let result = try await ask("change_summary", ["path": PathKey(worktree).path])
        guard let summary = DaemonWire.changeSummary(fromResult: result) else { throw Self.unrecognised }
        return summary
    }

    public func contents(of file: URL, atRevision revision: String, in worktree: URL) async throws -> String? {
        let result = try await ask("contents", [
            "path": PathKey(worktree).path, "file": PathKey(file).path, "revision": revision,
        ])
        guard let text = DaemonWire.contents(fromResult: result) else { throw Self.unrecognised }
        return text
    }

    public func mergeBase(of ref: String, in worktree: URL) async throws -> String? {
        let result = try await ask("merge_base", ["path": PathKey(worktree).path, "ref": ref])
        guard let sha = DaemonWire.mergeBase(fromResult: result) else { throw Self.unrecognised }
        return sha
    }

    public func upstream(in worktree: URL) async throws -> String? {
        let result = try await ask("upstream", ["path": PathKey(worktree).path])
        guard let upstream = DaemonWire.upstream(fromResult: result) else { throw Self.unrecognised }
        return upstream
    }

    public func shortstat(since sha: String, in worktree: URL) async throws -> GitChangeSummary? {
        let result = try await ask("shortstat", ["path": PathKey(worktree).path, "since": sha])
        guard let summary = DaemonWire.changeSummary(fromResult: result) else { throw Self.unrecognised }
        return summary
    }

    public func changedFiles(since sha: String, in worktree: URL) async throws -> [GitChangedFile] {
        let result = try await ask("changed_files", ["path": PathKey(worktree).path, "since": sha])
        guard let files = DaemonWire.changedFiles(fromResult: result) else { throw Self.unrecognised }
        return files
    }

    public func refs(in worktree: URL) async throws -> [GitRef] {
        let result = try await ask("refs", ["path": PathKey(worktree).path])
        guard let refs = DaemonWire.refs(fromResult: result) else { throw Self.unrecognised }
        return refs
    }

    public func recentCommits(limit: Int, in worktree: URL) async throws -> [GitCommit] {
        let result = try await ask("recent_commits", ["path": PathKey(worktree).path, "limit": max(limit, 0)])
        guard let commits = DaemonWire.commits(fromResult: result) else { throw Self.unrecognised }
        return commits
    }

    public func commit(matching revision: String, in worktree: URL) async throws -> GitCommit? {
        let result = try await ask("commit", ["path": PathKey(worktree).path, "revision": revision])
        guard let commit = DaemonWire.commit(fromResult: result) else { throw Self.unrecognised }
        return commit
    }

    public func fetchDefaultBranch(in repository: URL) async throws -> String? {
        let result = try await ask("fetch", ["path": repository.resolvingSymlinksInPath().path(percentEncoded: false)])
        guard let base = DaemonWire.fetchedBase(fromResult: result) else { throw Self.unrecognised }
        return base
    }

    public func addWorktree(in repository: URL, at path: URL, newBranch: String, from base: String) async throws {
        // Before resolving: `path` was built from `repository` as the caller
        // had it, so that is the pair that compares.
        var arguments: [String: Any] = [
            "path": repository.resolvingSymlinksInPath().path(percentEncoded: false),
            "worktree": path.path(percentEncoded: false),
            "new_branch": newBranch,
            "base": base,
        ]
        if let excluded = GitWorktreeLocation.topLevelFolder(of: path, inRepository: repository) {
            arguments["exclude"] = excluded
        }
        _ = try await ask("add_worktree", arguments)
    }

    // MARK: - The daemon

    private static let unrecognised = GitClientError.commandFailed("Unrecognised reply from herderd.")

    private func ask(_ op: String, _ arguments: [String: Any]) async throws -> [String: Any] {
        let id = nextID.next()
        let reply: Data
        do {
            reply = try await daemon.request(DaemonWire.gitRequest(id: id, op: op, arguments: arguments))
        } catch {
            throw GitClientError.commandFailed("herderd is not running")
        }
        return try DaemonWire.gitResult(fromReply: reply, id: id)
    }
}
