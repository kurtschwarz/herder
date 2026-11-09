#if DEBUG
import Core

/// `UpdaterClient` that finds nothing and counts how often it was asked to.
@MainActor
public final class StubUpdaterClient: UpdaterClient {
    public var automaticallyChecksForUpdates: Bool
    public private(set) var checks = 0

    public init(automaticallyChecksForUpdates: Bool = true) {
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }

    public func checkForUpdates() {
        checks += 1
    }
}
#endif
