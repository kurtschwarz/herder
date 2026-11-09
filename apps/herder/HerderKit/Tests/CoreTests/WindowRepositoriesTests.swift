import Foundation
import TestSupport
import Testing

@testable import Core

/// What one window lists, over the pool every window shares.
///
/// Per window, which is the point: opening a window used to show the same
/// sidebar as every other, because the order and the folds lived on the
/// repository itself.
@Suite @MainActor struct WindowRepositoriesTests {
    let bookmarks = InMemoryBookmarkClient()
    let git = StubGitClient()
    let state = InMemoryStateStore()
    let store: RepositoryStore
    let first: WindowRepositories
    let second: WindowRepositories

    init() {
        store = RepositoryStore(bookmarks: bookmarks, git: git, state: state)
        first = WindowRepositories(store: store)
        second = WindowRepositories(store: store)
    }

    @discardableResult
    func repository(_ path: String) -> URL {
        let url = URL(filePath: path)
        git.seed(url, .mainWorkingTree)
        return url
    }

    func names(_ list: WindowRepositories) -> [String] { list.repositories.map(\.name) }

    // MARK: - Listing

    @Test func aNewWindowListsNothing() {
        #expect(first.repositories.isEmpty)
    }

    /// The feature: a repository added in one window is not in another.
    @Test func whatOneWindowAddsAnotherDoesNotShow() async throws {
        try await first.add(url: repository("/code/api"))

        #expect(names(first) == ["api"])
        #expect(names(second).isEmpty)
    }

    @Test func newRepositoriesGoToTheBottom() async throws {
        for name in ["api", "web", "infra"] { try await first.add(url: repository("/code/\(name)")) }

        #expect(names(first) == ["api", "web", "infra"])
    }

    @Test func eachWindowKeepsItsOwnOrder() async throws {
        for name in ["api", "web"] { try await first.add(url: repository("/code/\(name)")) }
        for name in ["web", "api"] { try await second.add(url: repository("/code/\(name)")) }

        #expect(names(first) == ["api", "web"])
        #expect(names(second) == ["web", "api"])
    }

    // MARK: - Sharing the pool

    /// One folder, one record, however many windows list it.
    @Test func windowsListingOneFolderShareOneRecord() async throws {
        let url = repository("/code/api")
        let a = try await first.add(url: url)
        let b = try await second.add(url: url)

        #expect(a.id == b.id)
        #expect(store.repositories.count == 1)
        #expect(bookmarks.accessedURLs.count == 1)
    }

    /// A rename is the pool's, so it shows everywhere.
    @Test func aRenameShowsInEveryWindowListingIt() async throws {
        let url = repository("/code/api")
        let a = try await first.add(url: url)
        try await second.add(url: url)

        await first.rename(a, to: "backend")

        #expect(names(first) == ["backend"])
        #expect(names(second) == ["backend"])
    }

    // MARK: - Refusing

    @Test func aFolderThisWindowAlreadyListsIsRefused() async throws {
        let url = repository("/code/api")
        try await first.add(url: url)

        await #expect(throws: RepositoryStoreError.alreadyOpen(url)) {
            try await first.add(url: url)
        }
        #expect(names(first) == ["api"])
    }

    @Test func validatingRefusesTheSameThingAddingDoes() async throws {
        let url = repository("/code/api")
        try await first.add(url: url)

        await #expect(throws: RepositoryStoreError.alreadyOpen(url)) {
            try await first.validate(url: url)
        }
    }

    /// Listed elsewhere is not a reason to refuse.
    @Test func aFolderOnlyAnotherWindowListsIsAccepted() async throws {
        let url = repository("/code/api")
        try await first.add(url: url)

        #expect(try await second.validate(url: url) == .mainWorkingTree)
    }

    @Test func aFolderThatIsNotARepositoryIsRefused() async {
        await #expect(throws: RepositoryStoreError.notAGitRepository(URL(filePath: "/code/notes"))) {
            try await first.add(url: URL(filePath: "/code/notes"))
        }
    }

    // MARK: - Removing

    /// Taking it out of a window is not forgetting it: the record is the one
    /// thing the user cannot rebuild without picking the folder again.
    @Test func removingLeavesTheRecordInThePool() async throws {
        let url = repository("/code/api")
        let added = try await first.add(url: url)

        first.remove(added)

        #expect(first.repositories.isEmpty)
        #expect(store.repositories.map(\.id) == [added.id])
        #expect(!bookmarks.accessedURLs.isEmpty)
    }

    @Test func removingFromOneWindowLeavesTheOther() async throws {
        let url = repository("/code/api")
        let added = try await first.add(url: url)
        try await second.add(url: url)

        first.remove(added)

        #expect(names(second) == ["api"])
    }

    @Test func aRemovedFolderCanBeAddedAgainWithoutANewBookmark() async throws {
        let url = repository("/code/api")
        let added = try await first.add(url: url, name: "api")
        first.remove(added)

        let again = try await first.add(url: url)

        #expect(again == added)
        #expect(store.repositories.count == 1)
    }

    /// A record forgotten outright is skipped rather than drawn blank.
    @Test func aRecordDeletedFromThePoolDropsOutOfEveryWindow() async throws {
        let added = try await first.add(url: repository("/code/api"))

        await store.delete(added)

        #expect(first.repositories.isEmpty)
    }

    // MARK: - Folding

    @Test func foldingIsPerWindow() async throws {
        let url = repository("/code/api")
        let a = try await first.add(url: url)
        try await second.add(url: url)

        first.setCollapsed(a, true)

        #expect(first.isCollapsed(a))
        #expect(!second.isCollapsed(a))
    }

    @Test func aNewRepositoryStartsOpen() async throws {
        let added = try await first.add(url: repository("/code/api"))
        #expect(!first.isCollapsed(added))
    }

    // MARK: - Showing

    @Test func everythingListedStartsShown() async throws {
        for name in ["api", "web"] { try await first.add(url: repository("/code/\(name)")) }

        #expect(first.shown.map(\.name) == ["api", "web"])
    }

    @Test func aHiddenRepositoryIsListedButNotShown() async throws {
        let api = try await first.add(url: repository("/code/api"))
        try await first.add(url: repository("/code/web"))

        first.setShown(api, false)

        #expect(names(first) == ["api", "web"])
        #expect(first.shown.map(\.name) == ["web"])
        #expect(!first.isShown(api))
    }

    /// A sidebar with workspaces and nothing on it would look like it had none.
    @Test func theLastOneShowingCannotBeHidden() async throws {
        let api = try await first.add(url: repository("/code/api"))
        let web = try await first.add(url: repository("/code/web"))

        first.setShown(api, false)
        first.setShown(web, false)

        #expect(first.shown.map(\.name) == ["web"])
    }

    @Test func removingTheOnlyOneShowingShowsTheRest() async throws {
        let api = try await first.add(url: repository("/code/api"))
        let web = try await first.add(url: repository("/code/web"))
        first.setShown(api, false)

        first.remove(web)

        #expect(first.shown.map(\.name) == ["api"])
    }

    /// Ticking one while the fallback shows everything must not hide the rest.
    @Test func showingOneWhileAllAreHiddenKeepsTheOthersShowing() async throws {
        let api = try await first.add(url: repository("/code/api"))
        let web = try await first.add(url: repository("/code/web"))
        let infra = try await first.add(url: repository("/code/infra"))
        first.setShown(api, false)
        first.setShown(web, false)
        first.remove(infra)

        first.setShown(web, true)

        #expect(first.shown.map(\.name) == ["api", "web"])
    }

    @Test func showingAllUndoesEveryHide() async throws {
        let api = try await first.add(url: repository("/code/api"))
        let web = try await first.add(url: repository("/code/web"))
        try await first.add(url: repository("/code/infra"))
        first.setShown(api, false)
        first.setShown(web, false)

        first.showAll()

        #expect(first.shown.map(\.name) == ["api", "web", "infra"])
    }

    @Test func aRepositoryAddedLaterIsShown() async throws {
        let api = try await first.add(url: repository("/code/api"))
        try await first.add(url: repository("/code/web"))
        first.setShown(api, false)

        try await first.add(url: repository("/code/infra"))

        #expect(first.shown.map(\.name) == ["web", "infra"])
    }

    @Test func showingIsPerWindow() async throws {
        let url = repository("/code/api")
        let api = try await first.add(url: url)
        try await first.add(url: repository("/code/web"))
        try await second.add(url: url)
        try await second.add(url: repository("/code/web"))

        first.setShown(api, false)

        #expect(second.isShown(api))
    }

    @Test func aHiddenRepositoryStaysHiddenAcrossALaunch() async throws {
        let api = try await first.add(url: repository("/code/api"))
        try await first.add(url: repository("/code/web"))
        first.setShown(api, false)

        let restored = WindowRepositories(store: store, members: first.members)

        #expect(restored.shown.map(\.name) == ["web"])
    }

    @Test func hidingIsReportedAndARefusedHideIsNot() async throws {
        let api = try await first.add(url: repository("/code/api"))
        let web = try await first.add(url: repository("/code/web"))
        var changes = 0
        first.onChange = { changes += 1 }

        first.setShown(api, false)
        first.setShown(web, false)
        first.showAll()
        first.showAll()

        #expect(changes == 2)
    }

    // MARK: - Reordering

    @Test func reorderingMovesOnlyThisWindow() async throws {
        for name in ["api", "web", "infra"] {
            let url = repository("/code/\(name)")
            try await first.add(url: url)
            try await second.add(url: url)
        }

        var ordered = first.repositories
        ordered.insert(ordered.removeLast(), at: 0)
        first.reorder(to: ordered)

        #expect(names(first) == ["infra", "api", "web"])
        #expect(names(second) == ["api", "web", "infra"])
    }

    // MARK: - Telling the window

    /// What persists the window needs to hear that anything changed.
    @Test func everyChangeIsReported() async throws {
        var changes = 0
        first.onChange = { changes += 1 }
        let added = try await first.add(url: repository("/code/api"))
        first.setCollapsed(added, true)
        first.reorder(to: [added])
        first.remove(added)

        // The reorder changed nothing, so it is not a change.
        #expect(changes == 3)
    }

    @Test func aRepeatedFoldIsNotAChange() async throws {
        let added = try await first.add(url: repository("/code/api"))
        first.setCollapsed(added, true)
        var changes = 0
        first.onChange = { changes += 1 }

        first.setCollapsed(added, true)

        #expect(changes == 0)
    }

    // MARK: - Across a launch

    @Test func aWindowListsWhatItsSnapshotSays() async throws {
        let url = repository("/code/api")
        let added = try await first.add(url: url)
        first.setCollapsed(added, true)

        let restored = WindowRepositories(store: store, members: first.members)

        #expect(names(restored) == ["api"])
        #expect(restored.isCollapsed(added))
    }

    @Test func membershipSurvivesARoundTrip() throws {
        let member = RepositoryMembership(repositoryID: UUID(), isCollapsed: true)
        let decoded = try JSONDecoder().decode(RepositoryMembership.self, from: try JSONEncoder().encode(member))
        #expect(decoded == member)
    }

    /// Absent means open.
    @Test func membershipWithoutAFoldDecodesOpen() throws {
        let id = UUID()
        let decoded = try JSONDecoder().decode(
            RepositoryMembership.self,
            from: Data(#"{"repositoryID":"\#(id.uuidString)"}"#.utf8)
        )
        #expect(decoded == RepositoryMembership(repositoryID: id))
        #expect(!decoded.isHidden)
    }

    @Test func aHiddenMembershipSurvivesARoundTrip() throws {
        let member = RepositoryMembership(repositoryID: UUID(), isHidden: true)
        let decoded = try JSONDecoder().decode(RepositoryMembership.self, from: try JSONEncoder().encode(member))
        #expect(decoded == member)
    }
}
