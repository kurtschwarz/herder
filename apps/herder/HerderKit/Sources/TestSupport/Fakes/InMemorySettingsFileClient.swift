#if DEBUG
import Core
import Foundation
import Synchronization

/// `SettingsFileClient` over a string, so no test touches the user's
/// `~/.config`.
///
/// Like the real folder, it reports every change, the app's own writes
/// included: that is what echo suppression has to cope with.
public final class InMemorySettingsFileClient: SettingsFileClient {
    private struct State {
        var contents: String?
        var writes: [String] = []
        var readFailure: (any Error)?
        var continuations: [AsyncStream<Void>.Continuation] = []
    }

    public let url: URL
    private let state: Mutex<State>

    public init(
        url: URL = URL(filePath: "/Users/test/.config/herder/settings.json"),
        contents: String? = nil
    ) {
        self.url = url
        self.state = Mutex(State(contents: contents))
    }

    /// What is "on disk", or `nil` for no file.
    public var contents: String? {
        state.withLock { $0.contents }
    }

    /// Every write the app made, in order. ``edit(_:)`` is not here.
    public var writes: [String] {
        state.withLock { $0.writes }
    }

    public func read() async throws -> String? {
        try state.withLock {
            if let failure = $0.readFailure { throw failure }
            return $0.contents
        }
    }

    public func write(_ contents: String) async throws {
        state.withLock {
            $0.contents = contents
            $0.writes.append(contents)
        }
        notify()
    }

    public func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            state.withLock { $0.continuations.append(continuation) }
        }
    }

    /// Changes the file as another editor would, or deletes it with `nil`,
    /// and reports it.
    public func edit(_ contents: String?) {
        state.withLock { $0.contents = contents }
        notify()
    }

    /// Makes `read` throw `error` until called again with `nil`.
    public func refuseReads(with error: (any Error)?) {
        state.withLock { $0.readFailure = error }
    }

    /// Reports a change without making one.
    public func notify() {
        for continuation in state.withLock({ $0.continuations }) { continuation.yield() }
    }
}

extension UserSettingsStore {
    /// A store over an empty ``InMemorySettingsFileClient``, for a test or a
    /// preview that needs settings and does not look at the file.
    @MainActor
    public static func inMemory() -> UserSettingsStore {
        UserSettingsStore(file: InMemorySettingsFileClient(), clock: VirtualClockClient())
    }
}
#endif
