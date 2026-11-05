import Core
import Foundation
import Services
import Testing

/// A snapshot shaped like the real ones: a version, and a field added later
/// that older state will not carry.
///
/// `nonisolated` because this target defaults to `MainActor`, which would
/// otherwise isolate the synthesized `Codable` conformances and leave them
/// unable to satisfy `StateStore`'s `Sendable` requirement. The real snapshots
/// live in `Core`, which has no such default.
private nonisolated struct Snapshot: Codable, Sendable, Equatable {
    var version = 1
    var openTabs: [String]
    var activeTab: String?

    init(version: Int = 1, openTabs: [String], activeTab: String? = nil) {
        self.version = version
        self.openTabs = openTabs
        self.activeTab = activeTab
    }
}

/// These run in parallel and the store is a directory, so each test gets its
/// own root. A shared one would have tests reading each other's files.
@Suite struct FileStateStoreTests {
    private let root = URL.temporaryDirectory
        .appending(path: "herder-filestate-tests-\(UUID().uuidString)")

    private func makeStore() -> FileStateStore {
        FileStateStore(root: root)
    }

    // MARK: - The protocol

    @Test func nothingStoredReadsAsNil() async throws {
        let store = makeStore()
        #expect(try await store.load(Snapshot.self, forKey: "absent") == nil)
    }

    @Test func aSavedValueComesBack() async throws {
        let store = makeStore()
        let snapshot = Snapshot(openTabs: ["a.swift", "b.swift"], activeTab: "a.swift")

        try await store.save(snapshot, forKey: "workspace:/code/api")

        #expect(try await store.load(Snapshot.self, forKey: "workspace:/code/api") == snapshot)
    }

    @Test func savingTwiceReplaces() async throws {
        let store = makeStore()

        try await store.save(Snapshot(openTabs: ["first"]), forKey: "app")
        try await store.save(Snapshot(openTabs: ["second"]), forKey: "app")

        #expect(try await store.load(Snapshot.self, forKey: "app")?.openTabs == ["second"])
    }

    @Test func keysDoNotSeeEachOther() async throws {
        let store = makeStore()

        try await store.save(Snapshot(openTabs: ["one"]), forKey: "workspace:/code/api")
        try await store.save(Snapshot(openTabs: ["two"]), forKey: "workspace:/code/web")

        #expect(try await store.load(Snapshot.self, forKey: "workspace:/code/api")?.openTabs == ["one"])
        #expect(try await store.load(Snapshot.self, forKey: "workspace:/code/web")?.openTabs == ["two"])
    }

    @Test func removingLeavesNothing() async throws {
        let store = makeStore()
        try await store.save(Snapshot(openTabs: ["a"]), forKey: "app")

        try await store.remove(forKey: "app")

        #expect(try await store.load(Snapshot.self, forKey: "app") == nil)
    }

    @Test func removingSomethingAbsentIsNotAnError() async throws {
        try await makeStore().remove(forKey: "absent")
    }

    /// New fields decode with defaults, which is the whole migration strategy
    /// for snapshots. State written before a field existed must still load.
    @Test func stateMissingANewerFieldStillLoads() async throws {
        let store = makeStore()

        nonisolated struct Older: Codable, Sendable {
            var version = 1
            var openTabs: [String]
        }
        try await store.save(Older(openTabs: ["a.swift"]), forKey: "app")

        let loaded = try await store.load(Snapshot.self, forKey: "app")
        #expect(loaded?.openTabs == ["a.swift"])
        #expect(loaded?.activeTab == nil)
    }

    /// `load` throws for state it cannot read, and `loadIfReadable` does not.
    /// The app uses the second: a tab layout is not worth refusing to open a
    /// window over.
    @Test func unreadableStateThrowsButCanBeSkipped() async throws {
        let store = makeStore()
        try await store.save("not a snapshot", forKey: "app")

        await #expect(throws: (any Error).self) {
            try await store.load(Snapshot.self, forKey: "app")
        }
        #expect(await store.loadIfReadable(Snapshot.self, forKey: "app") == nil)
    }

    // MARK: - The layout on disk

    /// `ARCHITECTURE.md` names this file. Anything looking for what Herder
    /// remembers looks here first, and a user copying their setup to another
    /// Mac copies this.
    @Test func theAppSnapshotIsStateJSON() async throws {
        let store = makeStore()

        try await store.save(AppSnapshot(), forKey: AppSnapshot.persistenceKey)

        #expect(FileManager.default.fileExists(atPath: root.appending(path: "state.json").path))
    }

    @Test func aWorkspaceSnapshotGoesUnderWorkspaces() async throws {
        let store = makeStore()
        let key = WorkspaceSnapshot.persistenceKey(for: WorkspaceID(PathKey(canonical: "/code/api")))

        try await store.save(Snapshot(openTabs: ["a"]), forKey: key)

        let directory = root.appending(path: "workspaces")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.count == 1)
        // Readable, so the directory can be looked through by eye, and suffixed
        // so two worktrees called `main` cannot collide.
        #expect(files[0].hasPrefix("api-"))
        #expect(files[0].hasSuffix(".json"))
    }

    /// The whole point of files over a SQLite blob: what the app remembers can
    /// be read without the app.
    @Test func whatIsWrittenIsReadableJSON() async throws {
        let store = makeStore()

        try await store.save(Snapshot(openTabs: ["a.swift"]), forKey: AppSnapshot.persistenceKey)

        let text = try String(contentsOf: root.appending(path: "state.json"), encoding: .utf8)
        #expect(text.contains("\"openTabs\""))
        #expect(text.contains("a.swift"))
        // Pretty-printed, so a diff of this file is worth reading.
        #expect(text.contains("\n"))
    }

    /// Two worktrees under different repositories are routinely both called
    /// `main`. Keying the file on the last component alone would have one
    /// overwrite the other's layout.
    @Test func twoWorktreesWithTheSameNameDoNotCollide() async throws {
        let store = makeStore()
        let first = WorkspaceSnapshot.persistenceKey(for: WorkspaceID(PathKey(canonical: "/code/api/main")))
        let second = WorkspaceSnapshot.persistenceKey(for: WorkspaceID(PathKey(canonical: "/code/web/main")))

        try await store.save(Snapshot(openTabs: ["api"]), forKey: first)
        try await store.save(Snapshot(openTabs: ["web"]), forKey: second)

        #expect(try await store.load(Snapshot.self, forKey: first)?.openTabs == ["api"])
        #expect(try await store.load(Snapshot.self, forKey: second)?.openTabs == ["web"])
    }

    /// A file name is capped at 255 bytes, and a worktree can be nested deep
    /// enough to pass that. The name has to be bounded rather than the path
    /// spelled out, or the save throws and the workspace silently forgets.
    @Test func aVeryDeepPathStillSaves() async throws {
        let store = makeStore()
        let deep = "/" + Array(repeating: "a-rather-long-folder-name", count: 20).joined(separator: "/")
        let key = WorkspaceSnapshot.persistenceKey(for: WorkspaceID(PathKey(canonical: deep)))

        try await store.save(Snapshot(openTabs: ["deep"]), forKey: key)

        #expect(try await store.load(Snapshot.self, forKey: key)?.openTabs == ["deep"])
    }

    /// A folder starting with a dot must not make a hidden file: state nobody
    /// can see in a directory listing is state nobody can debug.
    @Test func aDotFolderDoesNotBecomeAHiddenFile() async throws {
        let store = makeStore()
        let key = WorkspaceSnapshot.persistenceKey(for: WorkspaceID(PathKey(canonical: "/code/.hidden")))

        try await store.save(Snapshot(openTabs: ["a"]), forKey: key)

        let files = try FileManager.default
            .contentsOfDirectory(atPath: root.appending(path: "workspaces").path)
        #expect(files.count == 1)
        #expect(!files[0].hasPrefix("."))
    }

    /// The name a key maps to has to be the same on the next launch. Swift's
    /// own hashing is seeded per process, so a store built on it would look for
    /// every file under a name it had never written.
    @Test func theSameKeyMapsToTheSameFileEveryTime() async throws {
        let key = "workspace:/code/api"
        let first = makeStore()
        try await first.save(Snapshot(openTabs: ["a"]), forKey: key)

        // A second store over the same directory stands in for a relaunch.
        let second = FileStateStore(root: root)

        #expect(try await second.load(Snapshot.self, forKey: key)?.openTabs == ["a"])
    }

    // MARK: - What the repository list depends on

    /// The one thing in Herder that cannot be rebuilt. It goes through
    /// `Codable` as base64 inside `state.json`, which is the Phase 7 decision
    /// (D13), so a round trip has to come back byte for byte.
    @Test func aBookmarkSurvivesTheRoundTrip() async throws {
        let store = makeStore()
        let bookmark = Data((0..<740).map { UInt8($0 % 251) })
        let snapshot = AppSnapshot(repositories: [
            Repository(name: "herder", path: "/code/herder", bookmark: bookmark, order: 0)
        ])

        try await store.save(snapshot, forKey: AppSnapshot.persistenceKey)

        let loaded = try await store.load(AppSnapshot.self, forKey: AppSnapshot.persistenceKey)
        #expect(loaded?.repositories.first?.bookmark == bookmark)
    }
}
