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
}

public enum FileClientError: Error, Equatable {
    case notFound(path: String)
    case notUTF8(path: String)
}
