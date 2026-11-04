import Clients
import Foundation
import Synchronization

/// `GitClient` whose answers are set by the test, so no test needs a real
/// repository on disk.
///
/// All state sits behind a lock because Swift Testing runs tests in parallel.
public final class StubGitClient: GitClient {
    private let kinds = Mutex<[String: GitRepositoryKind]>([:])

    public init() {}

    /// Declares what git would say about `url`. Anything unseeded is
    /// `.notARepository`, matching a disk with nothing on it.
    public func seed(_ url: URL, _ kind: GitRepositoryKind) {
        kinds.withLock { $0[FolderKey.of(url)] = kind }
    }

    public func repositoryKind(at url: URL) async throws -> GitRepositoryKind {
        kinds.withLock { $0[FolderKey.of(url)] } ?? .notARepository
    }
}
