#if DEBUG
import Core
import Foundation
import Synchronization

/// In-memory `FileClient` for tests, so no test touches disk.
///
/// Folders are keyed by `PathKey`, not by `URL`. The real file system does not
/// care whether a folder URL came with a trailing slash or how it was built, and
/// a fake that did would fail tests the live client passes.
///
/// All state sits behind a lock because Swift Testing runs tests in parallel.
public final class InMemoryFileClient: FileClient {
    private struct Folders {
        var children: [PathKey: [DirectoryEntry]] = [:]
        var unreadable: Set<PathKey> = []
        var reads: [URL] = []
        var moves: [Move] = []
        var creations: [DirectoryEntry] = []
    }

    private let storage = Mutex<[String: String]>([:])
    private let folders = Mutex(Folders())
    private let fileReads = Mutex<[String]>([])

    public init() {}

    /// Every path `read` has been handed, in order. The editor reads only the
    /// tab it is showing, and this is how a test sees the others left alone.
    public var reads: [String] {
        fileReads.withLock { $0 }
    }

    /// Forgets what has been read, so a test can assert about one phase of it.
    public func clearReads() {
        fileReads.withLock { $0 = [] }
    }

    /// Pre-populates a path without going through `write`.
    public func seed(_ path: String, _ contents: String) {
        storage.withLock { $0[path] = contents }
    }

    /// Everything currently "on disk", for assertions.
    public var files: [String: String] {
        storage.withLock { $0 }
    }

    public func read(_ path: String) async throws -> String {
        fileReads.withLock { $0.append(path) }
        guard let contents = storage.withLock({ $0[path] }) else {
            throw FileClientError.notFound(path: path)
        }
        return contents
    }

    public func read(_ path: String, maxBytes: Int) async throws -> String {
        let contents = try await read(path)
        guard contents.utf8.count <= maxBytes else { throw FileClientError.tooLarge(path: path) }
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
        let key = PathKey(url)
        folders.withLock {
            $0.children[key] = children
            $0.unreadable.remove(key)
        }
    }

    /// Makes `children(of:)` throw for `url`.
    public func seedUnreadable(_ url: URL) {
        folders.withLock { _ = $0.unreadable.insert(PathKey(url)) }
    }

    /// Every folder `children(of:)` has been asked about, in order.
    public var childReads: [URL] {
        folders.withLock { $0.reads }
    }

    public func children(of url: URL) async throws -> [DirectoryEntry] {
        let key = PathKey(url)
        return try folders.withLock {
            $0.reads.append(url)
            guard !$0.unreadable.contains(key), let children = $0.children[key] else {
                throw FileClientError.unreadable(path: url.path(percentEncoded: false))
            }
            return children
        }
    }

    public func move(_ source: URL, to destination: URL) async throws {
        let from = PathKey(source)
        let to = PathKey(destination)
        guard let parent = from.parent else {
            throw FileClientError.notFound(path: source.path(percentEncoded: false))
        }
        try folders.withLock { state in
            var siblings = state.children[parent] ?? []
            guard siblings.contains(where: { PathKey($0.url) == from }) else {
                throw FileClientError.notFound(path: source.path(percentEncoded: false))
            }
            guard !siblings.contains(where: { PathKey($0.url) == to }) else {
                throw FileClientError.alreadyExists(path: destination.path(percentEncoded: false))
            }
            siblings = siblings.map {
                PathKey($0.url) == from ? DirectoryEntry(url: destination, isDirectory: $0.isDirectory) : $0
            }
            state.children[parent] = siblings
            state.children[to] = state.children.removeValue(forKey: from)
            state.moves.append(Move(source: source, destination: destination))
        }
    }

    /// Every move made, in order.
    public var moves: [Move] {
        folders.withLock { $0.moves }
    }

    public struct Move: Equatable, Sendable {
        public var source: URL
        public var destination: URL

        public init(source: URL, destination: URL) {
            self.source = source
            self.destination = destination
        }
    }

    public func create(_ url: URL, isDirectory: Bool) async throws {
        let key = PathKey(url)
        guard let parent = key.parent else {
            throw FileClientError.unreadable(path: url.path(percentEncoded: false))
        }
        try folders.withLock { state in
            var siblings = state.children[parent] ?? []
            guard !siblings.contains(where: { PathKey($0.url) == key }) else {
                throw FileClientError.alreadyExists(path: url.path(percentEncoded: false))
            }
            siblings.append(DirectoryEntry(url: url, isDirectory: isDirectory))
            state.children[parent] = siblings
            if isDirectory { state.children[key] = [] }
            state.creations.append(DirectoryEntry(url: url, isDirectory: isDirectory))
        }
    }

    /// Every file and folder made, in order.
    public var creations: [DirectoryEntry] {
        folders.withLock { $0.creations }
    }
}
#endif
