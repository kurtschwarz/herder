#if DEBUG
import Core
import Synchronization

/// `LeftoverAgentClient` that ends nothing and counts how often it was asked.
public final class StubLeftoverAgentClient: LeftoverAgentClient {
    private let count = Mutex(0)

    public init() {}

    public var sweeps: Int { count.withLock { $0 } }

    public func endLeftovers() async {
        count.withLock { $0 += 1 }
    }
}
#endif
