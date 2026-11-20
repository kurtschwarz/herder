#if DEBUG
import Foundation

/// What `eventually` throws when the condition never held, which fails the
/// test with the message below. Thrown rather than recorded so TestSupport does
/// not link the Testing framework into the app.
public struct NeverHappened: Error, CustomStringConvertible {
    public let what: String
    public let timeout: Duration
    public let location: String

    public var description: String { "never happened within \(timeout): \(what) (\(location))" }
}

/// Waits until `condition` holds. The budget is a real deadline on a
/// `ContinuousClock`, not a count of polls, so a loaded machine that polls
/// slowly still gets the whole of it.
///
/// Runs on the caller's actor, so a main-actor test can pass a closure that
/// reads main-actor state.
public func eventually(
    _ what: String,
    timeout: Duration = .seconds(10),
    pollingEvery interval: Duration = .milliseconds(5),
    isolation: isolated (any Actor)? = #isolation,
    fileID: String = #fileID, line: Int = #line,
    _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            throw NeverHappened(what: what, timeout: timeout, location: "\(fileID):\(line)")
        }
        try await Task.sleep(for: interval)
    }
}
#endif
