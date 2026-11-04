import Clients
import Foundation
import Synchronization

/// In-memory `FileClient` for tests, so no test touches disk.
///
/// All state sits behind a lock because Swift Testing runs tests in parallel.
public final class InMemoryFileClient: FileClient {
    private let storage = Mutex<[String: String]>([:])

    public init() {}

    /// Pre-populates a path without going through `write`.
    public func seed(_ path: String, _ contents: String) {
        storage.withLock { $0[path] = contents }
    }

    /// Everything currently "on disk", for assertions.
    public var files: [String: String] {
        storage.withLock { $0 }
    }

    public func read(_ path: String) async throws -> String {
        guard let contents = storage.withLock({ $0[path] }) else {
            throw FileClientError.notFound(path: path)
        }
        return contents
    }

    public func write(_ contents: String, to path: String) async throws {
        storage.withLock { $0[path] = contents }
    }

    public func exists(_ path: String) async -> Bool {
        storage.withLock { $0[path] != nil }
    }
}
