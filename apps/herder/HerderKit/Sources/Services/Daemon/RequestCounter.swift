import Synchronization

/// Hands out the ids that tie each request to the daemon to its answer.
final class RequestCounter: Sendable {
    private let value = Mutex(0)

    func next() -> Int {
        value.withLock {
            $0 += 1
            return $0
        }
    }
}
