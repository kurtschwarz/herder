import Clients
import Foundation
import Models
import Synchronization

/// `GitClient` whose answers are set by the test, so no test needs a real
/// repository on disk.
///
/// All state sits behind a lock because Swift Testing runs tests in parallel.
public final class StubGitClient: GitClient {
    private let kinds = Mutex<[String: GitRepositoryKind]>([:])
    private let trees = Mutex<[String: [GitWorktree]]>([:])
    private let branchLists = Mutex<[String: [String]]>([:])
    private let added = Mutex<[AddedWorktree]>([])
    private let addFailure = Mutex<String?>(nil)
    private let unreadable = Mutex<Set<String>>([])
    private let gitDirectories = Mutex<[String: URL?]>([:])
    private let statuses = Mutex<[String: [String: GitStatus]]>([:])
    private let statusAsked = Mutex<[URL]>([])
    private let statusFails = Mutex(false)
    private let statusHeld = Mutex(false)
    private let statusWaiter = Mutex<CheckedContinuation<Void, Never>?>(nil)

    /// A call to `addWorktree`, as the stub saw it.
    public struct AddedWorktree: Equatable, Sendable {
        public var repository: URL
        public var path: URL
        public var newBranch: String
        public var base: String

        public init(repository: URL, path: URL, newBranch: String, base: String) {
            self.repository = repository
            self.path = path
            self.newBranch = newBranch
            self.base = base
        }
    }

    public init() {}

    /// Declares the local branches of the repository at `url`.
    public func seed(branches: [String], at url: URL) {
        branchLists.withLock { $0[FolderKey.of(url)] = branches }
    }

    /// Makes `addWorktree` throw `commandFailed(message)`.
    public func failAddingWorktrees(with message: String) {
        addFailure.withLock { $0 = message }
    }

    /// Every `addWorktree` call so far, in order.
    public var addedWorktrees: [AddedWorktree] {
        added.withLock { $0 }
    }

    /// Declares what git would say about `url`. Anything unseeded is
    /// `.notARepository`, matching a disk with nothing on it.
    public func seed(_ url: URL, _ kind: GitRepositoryKind) {
        kinds.withLock { $0[FolderKey.of(url)] = kind }
    }

    /// Declares the worktrees git would list for `url`, in display order.
    public func seed(worktrees: [GitWorktree], at url: URL) {
        trees.withLock { $0[FolderKey.of(url)] = worktrees }
    }

    /// Makes `worktrees(at:)` throw for `url`, as it would for a folder that
    /// vanished between being listed and being read.
    public func seedUnreadable(_ url: URL) {
        unreadable.withLock { _ = $0.insert(FolderKey.of(url)) }
    }

    /// Declares where the working tree at `worktree` keeps its index.
    public func seed(gitDirectory: URL?, of worktree: URL) {
        gitDirectories.withLock { $0[FolderKey.of(worktree)] = gitDirectory }
    }

    /// `<worktree>/.git` unless seeded otherwise, which is the layout of an
    /// ordinary repository.
    public func gitDirectory(of url: URL) async throws -> URL? {
        gitDirectories.withLock { $0[FolderKey.of(url)] } ?? url.appending(path: ".git")
    }

    /// Declares what git would say about the working tree at `worktree`, keyed
    /// by path relative to it, the way porcelain output is. Replaces any
    /// earlier seed.
    public func seed(status: [String: GitStatus], in worktree: URL) {
        statuses.withLock { $0[PathKey(worktree).path] = status }
    }

    /// The common case: these paths, relative to `worktree`, are ignored and
    /// nothing else has changed.
    public func seed(ignored paths: Set<String>, in worktree: URL) {
        seed(status: Dictionary(uniqueKeysWithValues: paths.map { ($0, GitStatus.ignored) }), in: worktree)
    }

    /// Makes `status(in:)` throw, as it would if git could not run.
    public func failStatusLookups(_ fails: Bool = true) {
        statusFails.withLock { $0 = fails }
    }

    /// Makes `status(in:)` wait, once asked, until `releaseStatusLookups()`.
    public func holdStatusLookups() {
        statusHeld.withLock { $0 = true }
    }

    public func releaseStatusLookups() {
        statusHeld.withLock { $0 = false }
        statusWaiter.withLock { waiter in
            defer { waiter = nil }
            return waiter
        }?.resume()
    }

    /// Every working tree `status(in:)` has been asked about, in order.
    public var statusLookups: [URL] {
        statusAsked.withLock { $0 }
    }

    public func status(in worktree: URL) async throws -> GitWorktreeStatus {
        if statusHeld.withLock({ $0 }) {
            // Recorded once the wait is in place, so a test that sees the
            // lookup can release it without racing the wait.
            await withCheckedContinuation { waiter in
                statusWaiter.withLock { $0 = waiter }
                statusAsked.withLock { $0.append(worktree) }
            }
        } else {
            statusAsked.withLock { $0.append(worktree) }
        }
        if statusFails.withLock({ $0 }) { throw GitClientError.commandFailed("git could not run") }

        let root = PathKey(worktree)
        let seeded = statuses.withLock { $0[root.path] } ?? [:]
        return GitWorktreeStatus(
            root: root,
            entries: Dictionary(uniqueKeysWithValues: seeded.map { (root.appending($0.key), $0.value) })
        )
    }

    public func repositoryKind(at url: URL) async throws -> GitRepositoryKind {
        kinds.withLock { $0[FolderKey.of(url)] } ?? .notARepository
    }

    public func worktrees(at url: URL) async throws -> [GitWorktree] {
        if unreadable.withLock({ $0.contains(FolderKey.of(url)) }) {
            throw StubGitClientError.unreadable
        }
        return trees.withLock { $0[FolderKey.of(url)] } ?? []
    }

    public func branches(at url: URL) async throws -> [String] {
        branchLists.withLock { $0[FolderKey.of(url)] } ?? []
    }

    public func addWorktree(
        in repository: URL,
        at path: URL,
        newBranch: String,
        from base: String
    ) async throws {
        if let message = addFailure.withLock({ $0 }) {
            throw GitClientError.commandFailed(message)
        }
        added.withLock {
            $0.append(AddedWorktree(repository: repository, path: path, newBranch: newBranch, base: base))
        }
    }
}

public enum StubGitClientError: Error, Equatable {
    case unreadable
}
