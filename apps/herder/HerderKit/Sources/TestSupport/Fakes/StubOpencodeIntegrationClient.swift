#if DEBUG
import Core
import Synchronization

/// `OpencodeIntegrationClient` that links nothing and counts how often it was
/// asked.
public final class StubOpencodeIntegrationClient: OpencodeIntegrationClient {
    private let count = Mutex(0)

    public init() {}

    public var installs: Int { count.withLock { $0 } }

    public func install() async {
        count.withLock { $0 += 1 }
    }
}
#endif
