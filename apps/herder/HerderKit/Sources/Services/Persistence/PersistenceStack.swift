import Core
import Foundation

/// Everything the app needs to persist itself, with the storage behind it kept
/// inside this module.
///
/// The composition root used to build a `ModelContainer` and hold it, which put
/// `import SwiftData` in the App target and gave the boundary rule — SwiftData
/// lives only under `Services/Persistence/` — nothing to stand on. Handing back
/// a `StateStore` instead meant the move to JSON files could replace this
/// type's insides without the App target noticing, which is what Phase 7 then
/// did. SwiftData is gone entirely; this is the seam that made removing it a
/// deletion rather than a rewrite.
public struct PersistenceStack {
    /// Where the app's own state goes. ``FileStateStore``, and the only
    /// implementation there is.
    public let state: any StateStore

    /// The user's `settings.json`. Not app state: the user edits it, and it
    /// has a schema. See `docs/adr/0004-user-settings-file.md`.
    public let settingsFile: any SettingsFileClient

    private init(state: any StateStore, settingsFile: any SettingsFileClient) {
        self.state = state
        self.settingsFile = settingsFile
    }

    /// Backed by files under Application Support, and the settings file under
    /// `~/.config/herder`. Used by the app.
    public static func live() throws -> PersistenceStack {
        PersistenceStack(
            state: try FileStateStore.live(),
            settingsFile: LiveSettingsFileClient(url: LiveSettingsFileClient.location(
                environment: ProcessInfo.processInfo.environment, home: .homeDirectory
            ))
        )
    }

    /// Backed by a fresh directory under the system temporary directory, unique
    /// per call so tests running in parallel cannot see each other's state.
    /// Used by tests and previews.
    ///
    /// Was `inMemory()` while SwiftData was underneath. It writes files now, so
    /// the name says what it is: nothing cleans these up, and they go where the
    /// system clears them.
    public static func temporary() -> PersistenceStack {
        let root = URL.temporaryDirectory.appending(path: "herder-state-\(UUID().uuidString)")
        return PersistenceStack(
            state: FileStateStore(root: root),
            settingsFile: LiveSettingsFileClient(url: root.appending(path: "config/herder/settings.json"))
        )
    }

    /// Where the state file lives, for a message that has to name it.
    public static func storeURL() throws -> URL {
        try FileStateStore.liveRoot().appending(path: "state.json")
    }
}
