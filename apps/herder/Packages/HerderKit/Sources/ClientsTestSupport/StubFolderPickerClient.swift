import Clients
import Foundation
import Synchronization

/// `FolderPickerClient` that answers with whatever the test scripted, so no
/// test opens a panel.
///
/// Each call consumes the next scripted answer; once they run out it behaves
/// like a user cancelling. `nil` can be scripted too, to model a cancel in the
/// middle of a sequence.
public final class StubFolderPickerClient: FolderPickerClient {
    private let state = Mutex(State())

    private struct State {
        var answers: [URL?] = []
        var requests = 0
    }

    public init() {}

    /// Queues the answer to the next `pickFolder()`.
    public func script(_ url: URL?) {
        state.withLock { $0.answers.append(url) }
    }

    /// How many times the picker was opened, for assertions.
    public var requests: Int {
        state.withLock { $0.requests }
    }

    @MainActor
    public func pickFolder() async -> URL? {
        state.withLock { state in
            state.requests += 1
            return state.answers.isEmpty ? nil : state.answers.removeFirst()
        }
    }
}
