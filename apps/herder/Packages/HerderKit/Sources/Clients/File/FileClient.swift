import Foundation

/// Everything the app is allowed to do to the file system.
///
/// One example of the pattern every client in this module follows: a protocol that
/// features depend on, a live implementation injected by the app target, and a fake
/// in `ClientsTestSupport` for tests.
public protocol FileClient: Sendable {
    func read(_ path: String) async throws -> String
    func write(_ contents: String, to path: String) async throws
    func exists(_ path: String) async -> Bool

    /// What is directly inside the folder at `url`, in no particular order.
    /// Throws for a folder that is missing or cannot be read.
    func children(of url: URL) async throws -> [DirectoryEntry]

    /// Moves the file or folder at `source` to `destination`. Throws
    /// `alreadyExists` rather than replacing what is there.
    func move(_ source: URL, to destination: URL) async throws
}

/// One item inside a folder.
public struct DirectoryEntry: Sendable, Equatable, Identifiable {
    public var url: URL

    /// Follows symlinks, so a link to a folder reads as a folder.
    public var isDirectory: Bool

    public var id: URL { url }
    public var name: String { url.lastPathComponent }

    public init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }
}

public enum FileClientError: Error, Equatable {
    case notFound(path: String)
    case notUTF8(path: String)
    case unreadable(path: String)
    case alreadyExists(path: String)
}
