import Core
import Foundation
import Storage
import SwiftData
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

@Suite struct SwiftDataStateStoreTests {
    private func makeStore() throws -> SwiftDataStateStore {
        SwiftDataStateStore(container: try WorkspaceContainer.inMemory())
    }

    @Test func nothingStoredReadsAsNil() async throws {
        let store = try makeStore()
        #expect(try await store.load(Snapshot.self, forKey: "absent") == nil)
    }

    @Test func aSavedValueComesBack() async throws {
        let store = try makeStore()
        let snapshot = Snapshot(openTabs: ["a.swift", "b.swift"], activeTab: "a.swift")

        try await store.save(snapshot, forKey: "workspace")

        #expect(try await store.load(Snapshot.self, forKey: "workspace") == snapshot)
    }

    /// The key is unique, so a second save has to replace rather than insert
    /// beside: a store that appended would fail the constraint, and one that
    /// read the wrong row would restore stale state.
    @Test func savingTwiceReplaces() async throws {
        let store = try makeStore()

        try await store.save(Snapshot(openTabs: ["first"]), forKey: "workspace")
        try await store.save(Snapshot(openTabs: ["second"]), forKey: "workspace")

        let loaded = try await store.load(Snapshot.self, forKey: "workspace")
        #expect(loaded?.openTabs == ["second"])
    }

    @Test func keysDoNotSeeEachOther() async throws {
        let store = try makeStore()

        try await store.save(Snapshot(openTabs: ["one"]), forKey: "a")
        try await store.save(Snapshot(openTabs: ["two"]), forKey: "b")

        #expect(try await store.load(Snapshot.self, forKey: "a")?.openTabs == ["one"])
        #expect(try await store.load(Snapshot.self, forKey: "b")?.openTabs == ["two"])
    }

    @Test func removingLeavesNothing() async throws {
        let store = try makeStore()
        try await store.save(Snapshot(openTabs: ["a"]), forKey: "workspace")

        try await store.remove(forKey: "workspace")

        #expect(try await store.load(Snapshot.self, forKey: "workspace") == nil)
    }

    @Test func removingSomethingAbsentIsNotAnError() async throws {
        let store = try makeStore()
        try await store.remove(forKey: "absent")
    }

    /// New fields decode with defaults, which is the whole migration strategy
    /// for snapshots. State written before a field existed must still load.
    @Test func stateMissingANewerFieldStillLoads() async throws {
        let store = try makeStore()

        // What an older build would have written: no `activeTab` at all.
        nonisolated struct Older: Codable, Sendable {
            var version = 1
            var openTabs: [String]
        }
        try await store.save(Older(openTabs: ["a.swift"]), forKey: "workspace")

        let loaded = try await store.load(Snapshot.self, forKey: "workspace")
        #expect(loaded?.openTabs == ["a.swift"])
        #expect(loaded?.activeTab == nil)
    }

    /// `load` throws for state it cannot read, and `loadIfReadable` does not.
    /// The app uses the second: a tab layout is not worth refusing to open a
    /// window over.
    @Test func unreadableStateThrowsButCanBeSkipped() async throws {
        let store = try makeStore()
        try await store.save("not a snapshot", forKey: "workspace")

        await #expect(throws: (any Error).self) {
            try await store.load(Snapshot.self, forKey: "workspace")
        }
        #expect(await store.loadIfReadable(Snapshot.self, forKey: "workspace") == nil)
    }

    /// Adding `StoredState` in schema V2 must not have disturbed the table the
    /// user's workspaces live in. They cannot be rebuilt from disk.
    @Test func workspacesAndStateShareOneStore() async throws {
        let container = try WorkspaceContainer.inMemory()
        let store = SwiftDataStateStore(container: container)

        try await store.save(Snapshot(openTabs: ["a"]), forKey: "workspace")

        let context = ModelContext(container)
        context.insert(Repository(name: "herder", path: "/herder", bookmark: Data(), order: 0))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Repository>()).count == 1)
        #expect(try await store.load(Snapshot.self, forKey: "workspace")?.openTabs == ["a"])
    }
}
