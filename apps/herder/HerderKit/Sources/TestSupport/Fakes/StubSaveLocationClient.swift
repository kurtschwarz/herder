#if DEBUG
import Core
import Foundation
import Synchronization

/// `SaveLocationClient` that answers with whatever the test scripted, so no
/// test opens a panel.
///
/// Each call consumes the next scripted answer; once they run out it behaves
/// like a user cancelling.
public final class StubSaveLocationClient: SaveLocationClient {
    private let state = Mutex(State())

    private struct State {
        var answers: [URL?] = []
        var requests: [Request] = []
    }

    /// What the panel was opened with.
    public struct Request: Equatable, Sendable {
        public let suggestedName: String
        public let directory: URL

        public init(suggestedName: String, directory: URL) {
            self.suggestedName = suggestedName
            self.directory = directory
        }
    }

    public init() {}

    /// Queues the answer to the next `chooseSaveLocation`.
    public func script(_ url: URL?) {
        state.withLock { $0.answers.append(url) }
    }

    /// Every opening of the panel, for assertions.
    public var requests: [Request] {
        state.withLock { $0.requests }
    }

    @MainActor
    public func chooseSaveLocation(suggestedName: String, startingAt directory: URL) async -> URL? {
        state.withLock { state in
            state.requests.append(Request(suggestedName: suggestedName, directory: directory))
            return state.answers.isEmpty ? nil : state.answers.removeFirst()
        }
    }
}
#endif
