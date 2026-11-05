import Core
import Foundation
import TestSupport
import Testing

/// The rules about adopting a folder: what may be added, what it is called,
/// where it sits, and what happens to the list across a launch.
///
/// Ported from `SwiftDataRepositoryStoreTests` when the list moved off
/// SwiftData in 4e. The assertions are the same; what changed is that a
/// `Repository` is now a value, so a test reads the result back off the store
/// rather than off the copy it is holding. Only the two OS-touching clients are
/// faked — the state store is real, in memory.
@Suite @MainActor struct RepositoryStoreTests {
    let bookmarks = InMemoryBookmarkClient()
    let git = StubGitClient()
    let state = InMemoryStateStore()
    let store: RepositoryStore

    init() {
        store = RepositoryStore(bookmarks: bookmarks, git: git, state: state)
    }

    /// A second store over the same saved state, standing in for the next
    /// launch. Loaded, because that is what launching does.
    func relaunch() async -> RepositoryStore {
        let next = RepositoryStore(bookmarks: bookmarks, git: git, state: state)
        await next.load()
        return next
    }

    /// What the store holds, which is what a view would draw.
    var repositories: [Repository] { store.repositories }

    func url(_ path: String) -> URL { URL(filePath: path) }

    @discardableResult
    func repository(_ path: String, kind: GitRepositoryKind = .mainWorkingTree) -> URL {
        let url = url(path)
        git.seed(url, kind)
        return url
    }

    // MARK: - Adding

    @Test func addsAMainWorkingTree() async throws {
        let url = repository("/code/api")

        let workspace = try await store.add(url: url)

        #expect(workspace.name == "api")
        #expect(workspace.path == "/code/api")
        #expect(repositories.map(\.id) == [workspace.id])
    }

    @Test func addsABareRepositoryWithoutItsGitSuffix() async throws {
        let url = repository("/code/api.git", kind: .bare)

        let workspace = try await store.add(url: url)
        #expect(workspace.name == "api")
    }

    @Test func takesAnExplicitNameOverTheFolderName() async throws {
        let url = repository("/code/api")

        let workspace = try await store.add(url: url, name: "Gateway")
        #expect(workspace.name == "Gateway")
    }

    @Test func refusesAFolderThatIsNotARepository() async throws {
        await #expect(throws: RepositoryStoreError.notAGitRepository(url("/code/notes"))) {
            _ = try await store.add(url: url("/code/notes"))
        }
        #expect(repositories.isEmpty)
    }

    @Test func refusesALinkedWorktreeAndNamesItsRepository() async throws {
        let main = url("/code/api")
        let worktree = repository("/code/feature", kind: .linkedWorktree(mainRepository: main))

        await #expect(throws: RepositoryStoreError.isLinkedWorktree(mainRepository: main)) {
            _ = try await store.add(url: worktree)
        }
    }

    @Test func refusesAFolderThatIsAlreadyOpen() async throws {
        let url = repository("/code/api")
        try await store.add(url: url)

        await #expect(throws: RepositoryStoreError.alreadyOpen(url)) {
            _ = try await store.add(url: url)
        }
        #expect(repositories.count == 1)
    }

    @Test func recognisesAFolderItAlreadyHasUnderAnewPath() async throws {
        let original = repository("/code/api")
        let workspace = try await store.add(url: original)

        // The folder moved: the bookmark follows it, the cached path has not.
        let moved = repository("/elsewhere/api")
        bookmarks.redirect(workspace.bookmark, to: moved)

        await #expect(throws: RepositoryStoreError.alreadyOpen(moved)) {
            _ = try await store.add(url: moved)
        }
    }

    // MARK: - Ordering

    // MARK: - Validating

    @Test func validatingReportsWhatGitMadeOfTheFolder() async throws {
        let url = repository("/code/api.git", kind: .bare)
        #expect(try await store.validate(url: url) == .bare)
    }

    @Test func validatingAddsNothing() async throws {
        let url = repository("/code/api")
        try await store.validate(url: url)
        #expect(repositories.isEmpty)
    }

    @Test func validatingRefusesWhatAddingRefuses() async throws {
        let main = url("/code/api")
        let worktree = repository("/code/feature", kind: .linkedWorktree(mainRepository: main))
        let open = repository("/code/web")
        try await store.add(url: open)

        await #expect(throws: RepositoryStoreError.notAGitRepository(url("/code/notes"))) {
            try await store.validate(url: url("/code/notes"))
        }
        await #expect(throws: RepositoryStoreError.isLinkedWorktree(mainRepository: main)) {
            try await store.validate(url: worktree)
        }
        await #expect(throws: RepositoryStoreError.alreadyOpen(open)) {
            try await store.validate(url: open)
        }
    }

    @Test func theDefaultNameIsWhatAddingWouldUse() async throws {
        let url = url("/code/api.git")
        #expect(RepositoryStore.defaultName(for: url, kind: .bare) == "api")
        #expect(RepositoryStore.defaultName(for: url, kind: .mainWorkingTree) == "api.git")
    }

    // MARK: - Renaming

    @Test func renamingPersistsTheNewName() async throws {
        let workspace = try await store.add(url: repository("/code/api"))

        await store.rename(workspace, to: "  Gateway ")

        #expect(repositories.first?.name == "Gateway")
        #expect(await relaunch().repositories.first?.name == "Gateway")
    }

    @Test func aBlankNameKeepsTheCurrentOne() async throws {
        let workspace = try await store.add(url: repository("/code/api"), name: "Gateway")

        await store.rename(workspace, to: "   ")

        #expect(repositories.first?.name == "Gateway")
    }

    @Test func twoWorkspacesMayShareAName() async throws {
        let first = try await store.add(url: repository("/code/api"), name: "api")
        let second = try await store.add(url: repository("/work/api"), name: "other")

        await store.rename(second, to: "api")

        #expect(repositories.map(\.name) == ["api", "api"])
        #expect(first.id != second.id)
    }

    @Test func newWorkspacesGoToTheBottom() async throws {
        for name in ["api", "web", "infra"] {
            try await store.add(url: repository("/code/\(name)"))
        }

        #expect(repositories.map(\.name) == ["api", "web", "infra"])
    }

    @Test func reorderingRenumbersEveryRow() async throws {
        for name in ["api", "web", "infra"] {
            try await store.add(url: repository("/code/\(name)"))
        }

        var ordered = repositories
        ordered.insert(ordered.removeLast(), at: 0)
        await store.reorder(to: ordered)

        let reloaded = repositories
        #expect(reloaded.map(\.name) == ["infra", "api", "web"])
        #expect(reloaded.map(\.order) == [0, 1, 2])
    }

    @Test func removingAWorkspaceLeavesTheOthersWhereTheyWere() async throws {
        for name in ["api", "web", "infra"] {
            try await store.add(url: repository("/code/\(name)"))
        }

        await store.delete(try #require(repositories.first))

        // The gap is deliberate: renumbering here would move rows the user never
        // touched, and would collide with an undone delete.
        let remaining = repositories
        #expect(remaining.map(\.name) == ["web", "infra"])
        #expect(remaining.map(\.order) == [1, 2])
    }

    @Test func addingAfterADeleteStillGoesToTheBottom() async throws {
        for name in ["api", "web"] {
            try await store.add(url: repository("/code/\(name)"))
        }
        await store.delete(try #require(repositories.first))

        try await store.add(url: repository("/code/infra"))
        #expect(repositories.map(\.name) == ["web", "infra"])
    }

    // MARK: - Deleting

    @Test func deletingLeavesTheFolderAlone() async throws {
        let url = repository("/code/api")
        let workspace = try await store.add(url: url)

        await store.delete(workspace)

        #expect(repositories.isEmpty)
        #expect(bookmarks.accessedURLs.isEmpty)
    }

    @Test func aDeletedFolderCanBeAddedAgain() async throws {
        let url = repository("/code/api")
        await store.delete(try await store.add(url: url))

        let readded = try await store.add(url: url)
        #expect(readded.name == "api")
        #expect(readded.order == 0)
    }

    // MARK: - Opening at launch

    @Test func openingTakesAccessToEveryFolder() async throws {
        try await store.add(url: repository("/code/api"))
        try await store.add(url: repository("/code/web"))

        let next = await relaunch()

        #expect(next.repositories.allSatisfy { $0.isAvailable })
        #expect(Set(next.access.openFolders.values) == [url("/code/api"), url("/code/web")])
    }

    @Test func openingRemakesAStaleBookmark() async throws {
        let url = repository("/code/api")
        try await store.add(url: url)
        bookmarks.markStale(url)

        let next = await relaunch()
        let reopened = try #require(next.repositories.first)

        #expect(reopened.isAvailable)
        #expect(try bookmarks.resolve(reopened.bookmark).isStale == false)
    }

    @Test func openingFollowsAFolderThatMoved() async throws {
        let workspace = try await store.add(url: repository("/code/api"))
        bookmarks.redirect(workspace.bookmark, to: url("/elsewhere/api"))

        let next = await relaunch()
        let reopened = try #require(next.repositories.first)

        #expect(reopened.path == "/elsewhere/api")
        // The name was fixed when the workspace was added and does not follow.
        #expect(reopened.name == "api")
    }

    @Test func anUnreachableFolderKeepsItsRowAndIsMarkedUnavailable() async throws {
        let url = repository("/volumes/backup/api")
        try await store.add(url: url)
        bookmarks.breakResolution(for: url)

        let next = await relaunch()
        let reopened = try #require(next.repositories.first)

        #expect(reopened.isAvailable == false)
        #expect(next.repositories.count == 1)
        #expect(next.access.openFolders.isEmpty)
    }

    @Test func aFolderThatComesBackIsAvailableOnTheNextOpen() async throws {
        let url = repository("/volumes/backup/api")
        try await store.add(url: url)
        bookmarks.breakResolution(for: url)
        await store.load()

        bookmarks.restoreResolution(for: url)
        await store.load()
        let reopened = try #require(repositories.first)

        #expect(reopened.isAvailable)
    }

    // MARK: - Relocating

    @Test func relocatingPointsTheSameWorkspaceAtANewFolder() async throws {
        let workspace = try await store.add(url: repository("/volumes/backup/api"), name: "Backup API")
        bookmarks.breakResolution(for: url("/volumes/backup/api"))
        await store.load()

        try await store.relocate(workspace, to: repository("/code/api"))

        let relocated = try #require(repositories.first)
        #expect(relocated.isAvailable)
        #expect(relocated.path == "/code/api")
        // Identity, name and position survive: it is the same repository.
        #expect(relocated.name == "Backup API")
        #expect(relocated.id == workspace.id)
    }

    @Test func relocatingRefusesAFolderThatIsNotARepository() async throws {
        let workspace = try await store.add(url: repository("/code/api"))

        await #expect(throws: RepositoryStoreError.notAGitRepository(url("/code/notes"))) {
            try await store.relocate(workspace, to: url("/code/notes"))
        }
        #expect(repositories.first?.path == "/code/api")
    }
}
