import Foundation

/// The passage of time.
///
/// Behind a protocol so a debounce can be tested without a test that waits for
/// one. Monotonic throughout: a change to the wall clock, from an NTP step or
/// the user, must not be able to stall a refresh or rush it.
public protocol ClockClient: Sendable {
    var now: ContinuousClock.Instant { get }

    /// Suspends for `duration`. Throws on cancellation.
    func sleep(for duration: Duration) async throws
}
