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
        var moves: [Move] = []
        var creations: [DirectoryEntry] = []
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

    public func move(_ source: URL, to destination: URL) async throws {
        let parent = source.deletingLastPathComponent()
        let path = destination.path(percentEncoded: false)
        try folders.withLock { state in
            // Seeded and asked-for URLs may differ by a trailing slash.
            func key(_ url: URL) -> URL {
                state.children.keys.first { $0.path == url.path } ?? url
            }
            let parentKey = key(parent)
            var siblings = state.children[parentKey] ?? []
            guard siblings.contains(where: { $0.url.path == source.path }) else {
                throw FileClientError.notFound(path: source.path(percentEncoded: false))
            }
            guard !siblings.contains(where: { $0.url.path == destination.path }) else {
                throw FileClientError.alreadyExists(path: path)
            }
            siblings = siblings.map {
                $0.url.path == source.path ? DirectoryEntry(url: destination, isDirectory: $0.isDirectory) : $0
            }
            state.children[parentKey] = siblings
            state.children[destination] = state.children.removeValue(forKey: key(source))
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
        let parent = url.deletingLastPathComponent()
        try folders.withLock { state in
            let parentKey = state.children.keys.first { $0.path == parent.path } ?? parent
            var siblings = state.children[parentKey] ?? []
            guard !siblings.contains(where: { $0.url.path == url.path }) else {
                throw FileClientError.alreadyExists(path: url.path(percentEncoded: false))
            }
            siblings.append(DirectoryEntry(url: url, isDirectory: isDirectory))
            state.children[parentKey] = siblings
            if isDirectory { state.children[url] = [] }
            state.creations.append(DirectoryEntry(url: url, isDirectory: isDirectory))
        }
    }

    /// Every file and folder made, in order.
    public var creations: [DirectoryEntry] {
        folders.withLock { $0.creations }
    }
}
