import Core
import Foundation
import SwiftData
import TestSupport
import Testing

@testable import Storage

/// Runs against a real in-memory `ModelContainer`, so the schema, the unique
/// constraint and the sort descriptors are the ones the app ships. Only the two
/// OS-touching clients are faked.
@Suite struct WorkspaceStoreTests {
    let bookmarks = InMemoryBookmarkClient()
    let git = StubGitClient()
    let container: ModelContainer
    let store: WorkspaceStore

    init() throws {
        container = try WorkspaceContainer.inMemory()
        store = WorkspaceStore(context: ModelContext(container), bookmarks: bookmarks, git: git)
    }

    /// A second store over the same data, standing in for the next launch.
    func relaunch() -> WorkspaceStore {
        WorkspaceStore(context: ModelContext(container), bookmarks: bookmarks, git: git)
    }

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
        #expect(try store.workspaces().map(\.id) == [workspace.id])
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
        await #expect(throws: WorkspaceStoreError.notAGitRepository(url("/code/notes"))) {
            _ = try await store.add(url: url("/code/notes"))
        }
        #expect(try store.workspaces().isEmpty)
    }

    @Test func refusesALinkedWorktreeAndNamesItsRepository() async throws {
        let main = url("/code/api")
        let worktree = repository("/code/feature", kind: .linkedWorktree(mainRepository: main))

        await #expect(throws: WorkspaceStoreError.isLinkedWorktree(mainRepository: main)) {
            _ = try await store.add(url: worktree)
        }
    }

    @Test func refusesAFolderThatIsAlreadyOpen() async throws {
        let url = repository("/code/api")
        try await store.add(url: url)

        await #expect(throws: WorkspaceStoreError.alreadyOpen(url)) {
            _ = try await store.add(url: url)
        }
        #expect(try store.workspaces().count == 1)
    }

    @Test func recognisesAFolderItAlreadyHasUnderAnewPath() async throws {
        let original = repository("/code/api")
        let workspace = try await store.add(url: original)

        // The folder moved: the bookmark follows it, the cached path has not.
        let moved = repository("/elsewhere/api")
        bookmarks.redirect(workspace.bookmark, to: moved)

        await #expect(throws: WorkspaceStoreError.alreadyOpen(moved)) {
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
        #expect(try store.workspaces().isEmpty)
    }

    @Test func validatingRefusesWhatAddingRefuses() async throws {
        let main = url("/code/api")
        let worktree = repository("/code/feature", kind: .linkedWorktree(mainRepository: main))
        let open = repository("/code/web")
        try await store.add(url: open)

        await #expect(throws: WorkspaceStoreError.notAGitRepository(url("/code/notes"))) {
            try await store.validate(url: url("/code/notes"))
        }
        await #expect(throws: WorkspaceStoreError.isLinkedWorktree(mainRepository: main)) {
            try await store.validate(url: worktree)
        }
        await #expect(throws: WorkspaceStoreError.alreadyOpen(open)) {
            try await store.validate(url: open)
        }
    }

    @Test func theDefaultNameIsWhatAddingWouldUse() async throws {
        let url = url("/code/api.git")
        #expect(WorkspaceStore.defaultName(for: url, kind: .bare) == "api")
        #expect(WorkspaceStore.defaultName(for: url, kind: .mainWorkingTree) == "api.git")
    }

    // MARK: - Renaming

    @Test func renamingPersistsTheNewName() async throws {
        let workspace = try await store.add(url: repository("/code/api"))

        try store.rename(workspace, to: "  Gateway ")

        #expect(workspace.name == "Gateway")
        #expect(try relaunch().workspaces().first?.name == "Gateway")
    }

    @Test func aBlankNameKeepsTheCurrentOne() async throws {
        let workspace = try await store.add(url: repository("/code/api"), name: "Gateway")

        try store.rename(workspace, to: "   ")

        #expect(workspace.name == "Gateway")
    }

    @Test func twoWorkspacesMayShareAName() async throws {
        let first = try await store.add(url: repository("/code/api"), name: "api")
        let second = try await store.add(url: repository("/work/api"), name: "other")

        try store.rename(second, to: "api")

        #expect(first.name == second.name)
        #expect(try store.workspaces().count == 2)
    }

    @Test func newWorkspacesGoToTheBottom() async throws {
        for name in ["api", "web", "infra"] {
            try await store.add(url: repository("/code/\(name)"))
        }

        #expect(try store.workspaces().map(\.name) == ["api", "web", "infra"])
    }

    @Test func reorderingRenumbersEveryRow() async throws {
        for name in ["api", "web", "infra"] {
            try await store.add(url: repository("/code/\(name)"))
        }

        var ordered = try store.workspaces()
        ordered.insert(ordered.removeLast(), at: 0)
        try store.reorder(to: ordered)

        let reloaded = try store.workspaces()
        #expect(reloaded.map(\.name) == ["infra", "api", "web"])
        #expect(reloaded.map(\.order) == [0, 1, 2])
    }

    @Test func removingAWorkspaceLeavesTheOthersWhereTheyWere() async throws {
        for name in ["api", "web", "infra"] {
            try await store.add(url: repository("/code/\(name)"))
        }

        try store.delete(try #require(try store.workspaces().first))

        // The gap is deliberate: renumbering here would move rows the user never
        // touched, and would collide with an undone delete.
        let remaining = try store.workspaces()
        #expect(remaining.map(\.name) == ["web", "infra"])
        #expect(remaining.map(\.order) == [1, 2])
    }

    @Test func addingAfterADeleteStillGoesToTheBottom() async throws {
        for name in ["api", "web"] {
            try await store.add(url: repository("/code/\(name)"))
        }
        try store.delete(try #require(try store.workspaces().first))

        try await store.add(url: repository("/code/infra"))
        #expect(try store.workspaces().map(\.name) == ["web", "infra"])
    }

    // MARK: - Deleting

    @Test func deletingLeavesTheFolderAlone() async throws {
        let url = repository("/code/api")
        let workspace = try await store.add(url: url)

        try store.delete(workspace)

        #expect(try store.workspaces().isEmpty)
        #expect(bookmarks.accessedURLs.isEmpty)
    }

    @Test func aDeletedFolderCanBeAddedAgain() async throws {
        let url = repository("/code/api")
        try store.delete(try await store.add(url: url))

        let readded = try await store.add(url: url)
        #expect(readded.name == "api")
        #expect(readded.order == 0)
    }

    // MARK: - Opening at launch

    @Test func openingTakesAccessToEveryFolder() async throws {
        try await store.add(url: repository("/code/api"))
        try await store.add(url: repository("/code/web"))

        let next = relaunch()
        let opened = try next.open()

        #expect(opened.allSatisfy { $0.isAvailable })
        #expect(Set(next.access.openFolders.values) == [url("/code/api"), url("/code/web")])
    }

    @Test func openingRemakesAStaleBookmark() async throws {
        let url = repository("/code/api")
        try await store.add(url: url)
        bookmarks.markStale(url)

        let next = relaunch()
        let reopened = try #require(try next.open().first)

        #expect(reopened.isAvailable)
        #expect(try bookmarks.resolve(reopened.bookmark).isStale == false)
    }

    @Test func openingFollowsAFolderThatMoved() async throws {
        let workspace = try await store.add(url: repository("/code/api"))
        bookmarks.redirect(workspace.bookmark, to: url("/elsewhere/api"))

        let next = relaunch()
        let reopened = try #require(try next.open().first)

        #expect(reopened.path == "/elsewhere/api")
        // The name was fixed when the workspace was added and does not follow.
        #expect(reopened.name == "api")
    }

    @Test func anUnreachableFolderKeepsItsRowAndIsMarkedUnavailable() async throws {
        let url = repository("/volumes/backup/api")
        try await store.add(url: url)
        bookmarks.breakResolution(for: url)

        let next = relaunch()
        let reopened = try #require(try next.open().first)

        #expect(reopened.isAvailable == false)
        #expect(try next.workspaces().count == 1)
        #expect(next.access.openFolders.isEmpty)
    }

    @Test func aFolderThatComesBackIsAvailableOnTheNextOpen() async throws {
        let url = repository("/volumes/backup/api")
        try await store.add(url: url)
        bookmarks.breakResolution(for: url)
        try store.open()

        bookmarks.restoreResolution(for: url)
        let reopened = try #require(try store.open().first)

        #expect(reopened.isAvailable)
    }

    // MARK: - Relocating

    @Test func relocatingPointsTheSameWorkspaceAtANewFolder() async throws {
        let workspace = try await store.add(url: repository("/volumes/backup/api"), name: "Backup API")
        bookmarks.breakResolution(for: url("/volumes/backup/api"))
        try store.open()

        try await store.relocate(workspace, to: repository("/code/api"))

        #expect(workspace.isAvailable)
        #expect(workspace.path == "/code/api")
        // Identity, name and position survive: it is the same workspace.
        #expect(workspace.name == "Backup API")
        #expect(try store.workspaces().map(\.id) == [workspace.id])
    }

    @Test func relocatingRefusesAFolderThatIsNotARepository() async throws {
        let workspace = try await store.add(url: repository("/code/api"))

        await #expect(throws: WorkspaceStoreError.notAGitRepository(url("/code/notes"))) {
            try await store.relocate(workspace, to: url("/code/notes"))
        }
        #expect(workspace.path == "/code/api")
    }
}
