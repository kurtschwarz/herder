import Core
import Foundation

public struct LiveClockClient: ClockClient {
    public init() {}

    public var now: ContinuousClock.Instant { ContinuousClock.now }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration, clock: ContinuousClock())
    }
}
