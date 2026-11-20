#if DEBUG
import Core
import Foundation
import Synchronization

/// ``NamingKeyVault`` in memory.
public final class InMemoryNamingKeyVault: NamingKeyVault {
    private let stored: Mutex<String?>

    public init(key: String? = nil) {
        stored = Mutex(key)
    }

    public var key: String? { stored.withLock { $0 } }

    public func load() throws -> String? { stored.withLock { $0 } }
    public func save(_ key: String) throws { stored.withLock { $0 = key } }
    public func delete() throws { stored.withLock { $0 = nil } }
}
#endif
