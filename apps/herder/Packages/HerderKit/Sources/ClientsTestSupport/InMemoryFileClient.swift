import Clients
import Foundation
import Synchronization

/// In-memory `FileClient` for tests, so no test touches disk.
///
/// All state sits behind a lock because Swift Testing runs tests in parallel.
public final class InMemoryFileClient: FileClient {
    private struct Folders {
        var children: [URL: [DirectoryEntry]] = [:]
        var unreadable: Set<URL> = []
        var reads: [URL] = []
    }

    private let storage = Mutex<[String: String]>([:])
    private let folders = Mutex(Folders())

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

    /// Sets what `children(of:)` returns for `url`. Replaces any earlier seed.
    public func seed(children: [DirectoryEntry], of url: URL) {
        folders.withLock {
            $0.children[url] = children
            $0.unreadable.remove(url)
        }
    }

    /// Makes `children(of:)` throw for `url`.
    public func seedUnreadable(_ url: URL) {
        folders.withLock { $0.unreadable.insert(url) }
    }

    /// Every folder `children(of:)` has been asked about, in order.
    public var childReads: [URL] {
        folders.withLock { $0.reads }
    }

    public func children(of url: URL) async throws -> [DirectoryEntry] {
        try folders.withLock {
            $0.reads.append(url)
            guard !$0.unreadable.contains(url), let children = $0.children[url] else {
                throw FileClientError.unreadable(path: url.path(percentEncoded: false))
            }
            return children
        }
    }
}
