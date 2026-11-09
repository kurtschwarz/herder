import Foundation

/// Finds and installs new releases of Herder.
///
/// Releases are published on GitHub with an appcast beside the DMG, and the
/// updater reads the one on the latest release. It asks before installing
/// anything: checking is the only thing it does on its own.
///
/// `@MainActor` and a class, because what it drives is the update window.
@MainActor
public protocol UpdaterClient: AnyObject {
    /// Whether it checks once a day without being asked. The updater keeps
    /// the user's choice itself.
    var automaticallyChecksForUpdates: Bool { get set }

    /// Checks now and shows what it found, including that nothing was. Asking
    /// during a check brings that check's window forward instead.
    func checkForUpdates()
}
