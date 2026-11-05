import Core
import Foundation

/// `FileClient` backed by the real file system.
///
/// Injected from the app target.
///
/// Every method is `@concurrent`: `FileManager` blocks, and a plain `nonisolated
/// async` function runs on whichever actor called it, which here is the main one.
/// The module's `nonisolated` default isolation is not enough on its own.
///
/// `FileManager` is not `Sendable`, so it is reached through `.default` inside each
/// call rather than stored. Tests use `InMemoryFileClient` instead of substituting
/// a different manager.
public struct LiveFileClient: FileClient {
    public init() {}

    @concurrent
    public func read(_ path: String) async throws -> String {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw FileClientError.notFound(path: path)
        }
        guard let contents = String(data: data, encoding: .utf8) else {
            throw FileClientError.notUTF8(path: path)
        }
        return contents
    }

    @concurrent
    public func read(_ path: String, maxBytes: Int) async throws -> String {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw FileClientError.notFound(path: path)
        }
        defer { try? handle.close() }
        // One byte more than allowed: enough to tell "exactly the limit" from
        // "over it" without reading the rest.
        let data: Data
        do {
            data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        } catch {
            throw FileClientError.unreadable(path: path)
        }
        guard data.count <= maxBytes else { throw FileClientError.tooLarge(path: path) }
        guard let contents = String(data: data, encoding: .utf8) else {
            throw FileClientError.notUTF8(path: path)
        }
        return contents
    }

    @concurrent
    public func write(_ contents: String, to path: String) async throws {
        let url = URL(filePath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url, options: .atomic)
    }

    @concurrent
    public func exists(_ path: String) async -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    @concurrent
    public func children(of url: URL) async throws -> [DirectoryEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: []
            )
        } catch {
            throw FileClientError.unreadable(path: url.path(percentEncoded: false))
        }
        return urls.map { child in
            // `.isDirectoryKey` does not follow symlinks, so resolve first.
            let resolved = child.resolvingSymlinksInPath()
            let isDirectory = (try? resolved.resourceValues(forKeys: keys).isDirectory) ?? false
            return DirectoryEntry(url: child, isDirectory: isDirectory)
        }
    }

    @concurrent
    public func move(_ source: URL, to destination: URL) async throws {
        // A rename that only changes case finds "something" at the destination:
        // the source itself, on a case-insensitive volume.
        let isCaseChange = source.deletingLastPathComponent() == destination.deletingLastPathComponent()
            && source.lastPathComponent.lowercased() == destination.lastPathComponent.lowercased()
        let path = destination.path(percentEncoded: false)
        if !isCaseChange, FileManager.default.fileExists(atPath: path) {
            throw FileClientError.alreadyExists(path: path)
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    @concurrent
    public func create(_ url: URL, isDirectory: Bool) async throws {
        let path = url.path(percentEncoded: false)
        guard !FileManager.default.fileExists(atPath: path) else {
            throw FileClientError.alreadyExists(path: path)
        }
        if isDirectory {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } else {
            guard FileManager.default.createFile(atPath: path, contents: Data()) else {
                throw FileClientError.unreadable(path: path)
            }
        }
    }
}
