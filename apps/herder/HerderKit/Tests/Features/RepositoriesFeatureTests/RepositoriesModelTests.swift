import Core
import Foundation
import TestSupport
import Testing

@testable import RepositoriesFeature

@Suite @MainActor struct RepositoriesModelTests {
    let bookmarks = InMemoryBookmarkClient()
    let git = StubGitClient()
    let state = InMemoryStateStore()
    let store: RepositoryStore
    let list: WindowRepositories
    let picker = StubFolderPickerClient()
    let model: RepositoriesModel

    init() throws {
        store = RepositoryStore(bookmarks: bookmarks, git: git, state: state)
        list = WindowRepositories(store: store)
        model = RepositoriesModel(repositories: list, git: git, picker: picker)
    }

    func addRepository(_ path: String) async throws -> Repository {
        let url = URL(filePath: path)
        git.seed(url, .mainWorkingTree)
        git.seed(worktrees: [GitWorktree(path: url, checkout: .branch("main"), isMainWorkingTree: true)], at: url)
        return try await list.add(url: url)
    }

    @Test func refreshReadsTheWorktreesOfOpenRepositories() async throws {
        let repository = try await addRepository("/code/api")

        await model.refresh([repository])

        #expect(model.listings[repository.id] == .loaded([
            GitWorktree(path: URL(filePath: "/code/api"), checkout: .branch("main"), isMainWorkingTree: true)
        ]))
    }

    @Test func aFolderThatCannotBeReadIsNotAnEmptyRepository() async throws {
        let repository = try await addRepository("/code/api")
        git.seedUnreadable(URL(filePath: "/code/api"))

        await model.refresh([repository])

        #expect(model.listings[repository.id] == .unreadable)
    }

    @Test func anUnavailableRepositoryIsNeitherReadNorExpanded() async throws {
        var repository = try await addRepository("/code/api")
        repository.isAvailable = false

        await model.refresh([repository])

        #expect(model.listings[repository.id] == nil)
        #expect(!model.isExpanded(repository))
    }

    @Test func workspacesStartExpanded() async throws {
        let repository = try await addRepository("/code/api")
        #expect(model.isExpanded(repository))
    }

    @Test func aCollapsedRepositoryIsNotRead() async throws {
        let repository = try await addRepository("/code/api")

        await model.toggle(repository)
        await model.refresh([repository])

        #expect(!model.isExpanded(repository))
        #expect(model.listings[repository.id] == nil)
    }

    @Test func expandingAgainReadsTheWorktrees() async throws {
        let repository = try await addRepository("/code/api")

        await model.toggle(repository)
        await model.toggle(repository)

        #expect(model.isExpanded(repository))
        #expect(model.listings[repository.id] != nil)
    }

    /// Folding is the user's arrangement of this window, so it is in the
    /// window's list and comes back with it rather than being redone every
    /// launch.
    @Test func collapsingSurvivesALaunch() async throws {
        let repository = try await addRepository("/code/api")
        await model.toggle(repository)

        let relaunched = RepositoryStore(bookmarks: bookmarks, git: git, state: state)
        await relaunched.load()
        let next = RepositoriesModel(
            repositories: WindowRepositories(store: relaunched, members: list.members),
            git: git,
            picker: picker
        )

        #expect(!next.isExpanded(try #require(relaunched.repositories.first)))
    }

    /// Folding in one window is not folding in another.
    @Test func collapsingIsPerWindow() async throws {
        let repository = try await addRepository("/code/api")
        let other = RepositoriesModel(
            repositories: WindowRepositories(store: store, members: [RepositoryMembership(repositoryID: repository.id)]),
            git: git,
            picker: picker
        )

        await model.toggle(repository)

        #expect(!model.isExpanded(repository))
        #expect(other.isExpanded(repository))
    }

    /// Removing takes it out of this window and nothing else: the record and
    /// its bookmark stay, because they cannot be rebuilt.
    @Test func removingTakesTheRepositoryOutOfThisWindowOnly() async throws {
        let repository = try await addRepository("/code/api")
        let id = repository.id
        await model.refresh([repository])

        model.remove(repository)

        #expect(model.repositories.isEmpty)
        #expect(model.listings[id] == nil)
        #expect(store[id] != nil)
    }

    /// The name is the pool's, so a rename elsewhere is seen here without
    /// reading the worktrees again.
    @Test func theNameOfARepositoryFollowsARenameInAnotherWindow() async throws {
        let repository = try await addRepository("/code/api")
        await model.refresh([repository])
        let other = WindowRepositories(store: store, members: list.members)

        await other.rename(repository, to: "Gateway")

        #expect(model.nameOfRepository(holding: URL(filePath: "/code/api")) == "Gateway")
    }

    @Test func committingARenameEndsEditingAndSavesTheName() async throws {
        let repository = try await addRepository("/code/api")
        model.renaming = repository.id

        await model.commitRename(repository, to: "Gateway")

        #expect(model.renaming == nil)
        #expect(store.repositories.first?.name == "Gateway")
    }

    @Test func committingABlankRenameKeepsTheName() async throws {
        let repository = try await addRepository("/code/api")
        model.renaming = repository.id

        await model.commitRename(repository, to: "")

        #expect(model.renaming == nil)
        #expect(store.repositories.first?.name == "api")
    }

    @Test func beginningToAddOpensTheModalOnce() {
        model.beginAdding()
        let first = model.adding
        model.beginAdding()

        #expect(first != nil)
        #expect(model.adding === first)
    }

    @Test func cancellingClosesTheModal() {
        model.beginAdding()
        model.cancelAdding()
        #expect(model.adding == nil)
    }

    @Test func submittingClosesTheModalOnceTheRepositoryIsAdded() async throws {
        let url = URL(filePath: "/code/api")
        git.seed(url, .mainWorkingTree)
        picker.script(url)
        model.beginAdding()
        await model.adding?.browse()

        await model.submitAdding()

        #expect(model.adding == nil)
        #expect(store.repositories.count == 1)
    }

    @Test func aRefusedSubmitLeavesTheModalUp() async throws {
        let url = URL(filePath: "/code/api")
        git.seed(url, .mainWorkingTree)
        picker.script(url)
        model.beginAdding()
        await model.adding?.browse()
        git.seed(url, .notARepository)

        await model.submitAdding()

        #expect(model.adding?.refusal == .notARepository)
    }

    // MARK: - New session

    @Test func aNewSessionOpensForAnAvailableRepository() async throws {
        let repository = try await addRepository("/code/api")

        model.beginNewSession(in: repository)

        #expect(model.newSession?.repositoryName == "api")
        #expect(model.isModalPresented)
    }

    @Test func anUnavailableRepositoryCannotStartASession() async throws {
        var repository = try await addRepository("/code/api")
        repository.isAvailable = false

        model.beginNewSession(in: repository)

        #expect(model.newSession == nil)
    }

    @Test func onlyOneModalAtATime() async throws {
        let repository = try await addRepository("/code/api")
        model.beginAdding()

        model.beginNewSession(in: repository)
        #expect(model.newSession == nil)

        model.cancelAdding()
        model.beginNewSession(in: repository)
        model.beginAdding()
        #expect(model.adding == nil)
    }

    @Test func creatingAWorktreeClosesTheModalAndShowsIt() async throws {
        let repository = try await addRepository("/code/api")
        let url = URL(filePath: "/code/api")
        git.seed(branches: ["main"], at: url)
        model.beginNewSession(in: repository)
        let session = try #require(model.newSession)
        await session.load()
        session.editBranchName("fix")
        // What git would now list, once the worktree exists.
        let created = GitWorktree(path: url.appending(path: "fix"), checkout: .branch("fix"), isMainWorkingTree: false)

        git.seed(worktrees: [created], at: url)
        await model.submitNewSession()

        #expect(model.newSession == nil)
        #expect(git.addedWorktrees.count == 1)
        #expect(model.listings[repository.id] == .loaded([created]))
    }

    @Test func aRefusedCreateLeavesTheModalUp() async throws {
        let repository = try await addRepository("/code/api")
        git.seed(branches: ["main"], at: URL(filePath: "/code/api"))
        git.failAddingWorktrees(with: "no")
        model.beginNewSession(in: repository)
        let session = try #require(model.newSession)
        await session.load()
        session.editBranchName("fix")

        await model.submitNewSession()

        #expect(model.newSession != nil)
        #expect(session.failure == "no")
    }

    // MARK: - Which repository a worktree belongs to
    //
    // These replace four tests about `selectedWorktree`, which this model no
    // longer owns: which workspace is active is the window's, in `WindowEnvironment`.
    // What is left here is the association the old selection kept by hand — and
    // which the listings already knew — plus the panes' need to name it.

    @Test func aWorktreeIsNamedAfterTheRepositoryHoldingIt() async throws {
        let repository = try await addRepository("/code/api")
        git.seed(worktrees: [
            GitWorktree(path: URL(filePath: "/code/api"), checkout: .branch("main"), isMainWorkingTree: true),
        ], at: URL(filePath: "/code/api"))

        await model.refresh(repository)

        #expect(model.nameOfRepository(holding: URL(filePath: "/code/api")) == repository.name)
    }

    /// A worktree the list has never seen belongs to nothing it can name, so a
    /// pane showing it has no repository name to put in its header.
    @Test func aWorktreeNoRepositoryClaimsHasNoName() async throws {
        let repository = try await addRepository("/code/api")
        await model.refresh(repository)

        #expect(model.nameOfRepository(holding: URL(filePath: "/code/api-gone")) == nil)
    }

    @Test func aWorktreeThatIsStillThereKeepsItsName() async throws {
        let repository = try await addRepository("/code/api")
        git.seed(worktrees: [
            GitWorktree(path: URL(filePath: "/code/api"), checkout: .branch("main"), isMainWorkingTree: true),
        ], at: URL(filePath: "/code/api"))

        await model.refresh(repository)
        await model.refresh(repository)

        #expect(model.nameOfRepository(holding: URL(filePath: "/code/api")) == "api")
    }

    @Test func removingARepositoryForgetsItsWorktrees() async throws {
        let repository = try await addRepository("/code/api")
        git.seed(worktrees: [
            GitWorktree(path: URL(filePath: "/code/api"), checkout: .branch("main"), isMainWorkingTree: true),
        ], at: URL(filePath: "/code/api"))
        await model.refresh(repository)

        await model.remove(repository)

        #expect(model.nameOfRepository(holding: URL(filePath: "/code/api")) == nil)
    }

    /// A rename has to show in the pane header, which reads this.
    @Test func renamingARepositoryChangesWhatItsWorktreesAreNamedAfter() async throws {
        let repository = try await addRepository("/code/api")
        git.seed(worktrees: [
            GitWorktree(path: URL(filePath: "/code/api"), checkout: .branch("main"), isMainWorkingTree: true),
        ], at: URL(filePath: "/code/api"))
        await model.refresh(repository)

        await model.commitRename(repository, to: "API")

        #expect(model.nameOfRepository(holding: URL(filePath: "/code/api")) == "API")
    }
}
