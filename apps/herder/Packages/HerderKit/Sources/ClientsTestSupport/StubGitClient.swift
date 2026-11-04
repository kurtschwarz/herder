import Clients
import Foundation
import Synchronization

/// `GitClient` whose answers are set by the test, so no test needs a real
/// repository on disk.
///
/// All state sits behind a lock because Swift Testing runs tests in parallel.
public final class StubGitClient: GitClient {
    private let kinds = Mutex<[String: GitRepositoryKind]>([:])
    private let trees = Mutex<[String: [GitWorktree]]>([:])

    public init() {}

    /// Declares what git would say about `url`. Anything unseeded is
    /// `.notARepository`, matching a disk with nothing on it.
    public func seed(_ url: URL, _ kind: GitRepositoryKind) {
        kinds.withLock { $0[FolderKey.of(url)] = kind }
    }

    /// Declares the worktrees git would list for `url`, in display order.
    public func seed(worktrees: [GitWorktree], at url: URL) {
        trees.withLock { $0[FolderKey.of(url)] = worktrees }
    }

    public func repositoryKind(at url: URL) async throws -> GitRepositoryKind {
        kinds.withLock { $0[FolderKey.of(url)] } ?? .notARepository
    }

    public func worktrees(at url: URL) async throws -> [GitWorktree] {
        trees.withLock { $0[FolderKey.of(url)] } ?? []
    }
}
