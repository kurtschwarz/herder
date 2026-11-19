import Core
import Foundation
import Synchronization

/// `GitClient` that asks herderd, bound to the one host it runs on. See ADR 0002.
///
/// Only `repositoryKind` goes to the daemon so far. The rest are still answered
/// by `local`, a `LiveGitClient`, until each is ported; when the last one is,
/// `local` and `LiveGitClient` are deleted and the daemon being unreachable is
/// the only way a call fails.
public struct DaemonGitClient: GitClient {
    private let daemon: any DaemonClient
    private let local: LiveGitClient
    private let nextID = Counter()

    public init(daemon: any DaemonClient, local: LiveGitClient = LiveGitClient()) {
        self.daemon = daemon
        self.local = local
    }

    // MARK: - Moved

    public func repositoryKind(at url: URL) async throws -> GitRepositoryKind {
        let result = try await ask("repository_kind", ["path": url.path(percentEncoded: false)])
        guard let kind = DaemonWire.repositoryKind(fromResult: result) else {
            throw GitClientError.commandFailed("Unrecognised reply from herderd.")
        }
        return kind
    }

    // MARK: - Still local

    public func worktrees(at url: URL) async throws -> [GitWorktree] {
        try await local.worktrees(at: url)
    }

    public func branches(at url: URL) async throws -> [String] {
        try await local.branches(at: url)
    }

    public func addWorktree(in repository: URL, at path: URL, newBranch: String, from base: String) async throws {
        try await local.addWorktree(in: repository, at: path, newBranch: newBranch, from: base)
    }

    public func gitDirectory(of url: URL) async throws -> URL? {
        try await local.gitDirectory(of: url)
    }

    public func checkout(of url: URL) async throws -> GitWorktree.Checkout? {
        try await local.checkout(of: url)
    }

    public func status(in worktree: URL) async throws -> GitWorktreeStatus {
        try await local.status(in: worktree)
    }

    public func changeSummary(in worktree: URL) async throws -> GitChangeSummary? {
        try await local.changeSummary(in: worktree)
    }

    public func contents(of file: URL, atRevision revision: String, in worktree: URL) async throws -> String? {
        try await local.contents(of: file, atRevision: revision, in: worktree)
    }

    public func mergeBase(of ref: String, in worktree: URL) async throws -> String? {
        try await local.mergeBase(of: ref, in: worktree)
    }

    public func upstream(in worktree: URL) async throws -> String? {
        try await local.upstream(in: worktree)
    }

    public func shortstat(since sha: String, in worktree: URL) async throws -> GitChangeSummary? {
        try await local.shortstat(since: sha, in: worktree)
    }

    public func changedFiles(since sha: String, in worktree: URL) async throws -> [GitChangedFile] {
        try await local.changedFiles(since: sha, in: worktree)
    }

    public func refs(in worktree: URL) async throws -> [GitRef] {
        try await local.refs(in: worktree)
    }

    public func recentCommits(limit: Int, in worktree: URL) async throws -> [GitCommit] {
        try await local.recentCommits(limit: limit, in: worktree)
    }

    public func commit(matching revision: String, in worktree: URL) async throws -> GitCommit? {
        try await local.commit(matching: revision, in: worktree)
    }

    // MARK: - The daemon

    private func ask(_ op: String, _ arguments: [String: String]) async throws -> [String: Any] {
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

private final class Counter: Sendable {
    private let value = Mutex(0)

    func next() -> Int {
        value.withLock {
            $0 += 1
            return $0
        }
    }
}
