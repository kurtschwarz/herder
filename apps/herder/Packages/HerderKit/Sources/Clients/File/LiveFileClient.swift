import Foundation

/// `FileClient` backed by the real file system.
///
/// Injected from the app target. Blocking `FileManager` work stays off the main
/// actor because this module's default isolation is `nonisolated`.
///
/// `FileManager` is not `Sendable`, so it is reached through `.default` inside each
/// call rather than stored. Tests use `InMemoryFileClient` instead of substituting
/// a different manager.
public struct LiveFileClient: FileClient {
    public init() {}

    public func read(_ path: String) async throws -> String {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw FileClientError.notFound(path: path)
        }
        guard let contents = String(data: data, encoding: .utf8) else {
            throw FileClientError.notUTF8(path: path)
        }
        return contents
    }

    public func write(_ contents: String, to path: String) async throws {
        let url = URL(filePath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url, options: .atomic)
    }

    public func exists(_ path: String) async -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

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
}
