import Core
import Sparkle

/// ``UpdaterClient`` over Sparkle's standard updater and its windows.
///
/// The feed URL and the key updates are signed with are in `Info.plist`, as
/// `SUFeedURL` and `SUPublicEDKey`. The private half of that key is a CI
/// secret, and `.github/workflows/herder-package.yml` signs each DMG with it.
@MainActor
public final class SparkleUpdaterClient: UpdaterClient {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    public init() {}

    public var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    public func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
