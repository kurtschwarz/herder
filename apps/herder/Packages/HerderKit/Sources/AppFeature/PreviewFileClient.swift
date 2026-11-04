#if DEBUG
import Clients

/// Does-nothing `FileClient` for SwiftUI previews. Debug-only so it never reaches a
/// release build; tests use `InMemoryFileClient` from `ClientsTestSupport` instead.
struct PreviewFileClient: FileClient {
    func read(_ path: String) async throws -> String { "" }
    func write(_ contents: String, to path: String) async throws {}
    func exists(_ path: String) async -> Bool { true }
}
#endif
