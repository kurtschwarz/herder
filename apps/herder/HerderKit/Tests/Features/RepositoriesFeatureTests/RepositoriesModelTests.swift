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
        model = RepositoriesModel(
            repositories: list, git: git, picker: picker, namer: StubSessionNamer(),
            naming: NamingSettings(settings: .inMemory(), vault: InMemoryNamingKeyVault()),
            agents: AgentCatalog(state: InMemoryStateStore(), settings: .inMemory())
        )
    }

    func addRepository(_ path: String) async throws -> Repository {
        let url = URL(filePath: path)
        git.seed(url, .mainWorkingTree)
        git.seed(worktrees: [GitWorktree(path: url, checkout: .branch("main"), isMainWorkingTree: true)], at: url)
        return try await list.add(url: url)
    }

    @Test func searchingFiltersWorkspacesByNameIgnoringCaseAndDiacritics() async throws {
        _ = try await addRepository("/code/Café")
        _ = try await addRepository("/code/api")

        #expect(model.matching("cafe").map(\.name) == ["Café"])
        #expect(model.matching("AP").map(\.name) == ["api"])
        #expect(model.matching("").count == 2)
    }

    @Test func searchingDoesNotLookAtPaths() async throws {
        _ = try await addRepository("/code/api")

        #expect(model.matching("code").isEmpty)
    }

    @Test func returnActsOnlyWhenOneWorkspaceMatches() async throws {
        let api = try await addRepository("/code/api")
        _ = try await addRepository("/code/app")

        #expect(model.soleMatch(for: "api")?.id == api.id)
        #expect(model.soleMatch(for: "ap") == nil)
        #expect(model.soleMatch(for: "zzz") == nil)
        #expect(model.soleMatch(for: "") == nil)
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

    @Test func anUnavailableRepositoryIsNotRead() async throws {
        var repository = try await addRepository("/code/api")
        repository.isAvailable = false

        await model.refresh([repository])

        #expect(model.listings[repository.id] == nil)
    }

    /// Nothing folds any more, so a repository folded by an earlier build is
    /// read like any other.
    @Test func aRepositoryFoldedBeforeIsStillRead() async throws {
        let repository = try await addRepository("/code/api")
        list.setCollapsed(repository, true)

        await model.refresh([repository])

        #expect(model.listings[repository.id] != nil)
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

    // MARK: - Workspace selector

    @Test func theSelectorIsNamedAfterWhatIsShowing() async throws {
        let api = try await addRepository("/code/api")
        #expect(model.selectionTitle == "api")

        _ = try await addRepository("/code/web")
        #expect(model.selectionTitle == "All workspaces")

        _ = try await addRepository("/code/infra")
        model.setShown(api, false)
        #expect(model.selectionTitle == "2 workspaces")
    }

    @Test func aSingleChoiceIsNamedAfterIt() async throws {
        let api = try await addRepository("/code/api")
        _ = try await addRepository("/code/web")

        #expect(model.selectionTitle(for: [api.id]) == "api")
        #expect(model.selectionTitle(for: []) == "Workspaces")
    }

    @Test func settingTheShownSetSwapsEvenTheLastOne() async throws {
        let api = try await addRepository("/code/api")
        let web = try await addRepository("/code/web")
        _ = try await addRepository("/code/infra")
        model.setShown([api.id])

        model.setShown([web.id])

        #expect(model.shownRepositories.map(\.name) == ["web"])
    }

    @Test func theLastOneShowingCannotBeUnticked() async throws {
        let api = try await addRepository("/code/api")
        let web = try await addRepository("/code/web")

        model.setShown(api, false)

        #expect(!model.canHide(web))
        #expect(model.shownRepositories.map(\.name) == ["web"])
    }

    @Test func selectingAllShowsEveryRepository() async throws {
        let api = try await addRepository("/code/api")
        _ = try await addRepository("/code/web")
        model.setShown(api, false)

        model.showAll()

        #expect(model.shownRepositories.map(\.name) == ["api", "web"])
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

    @Test func switchingRepositoryKeepsTheBranchNameAndResetsTheRest() async throws {
        let api = try await addRepository("/code/api")
        let web = try await addRepository("/code/web")
        git.seed(branches: ["main", "dev"], at: URL(filePath: "/code/api"))
        model.beginNewSession(in: api)
        let first = try #require(model.newSession)
        await first.load()
        first.editBranchName("fix")
        first.baseBranch = "dev"

        model.switchNewSession(to: web)

        let second = try #require(model.newSession)
        #expect(second !== first)
        #expect(second.repositoryName == "web")
        #expect(second.branchName == "fix")
        #expect(second.choice == .newWorktree)
        #expect(second.baseBranch.isEmpty)
        #expect(second.failure == nil)
        #expect(model.newSessionRepository?.id == web.id)
    }

    @Test func aNewSessionStartsInTheActiveWorktreesRepositoryElseTheFirst() async throws {
        let api = try await addRepository("/code/api")
        let web = try await addRepository("/code/web")
        await model.refresh([api, web])

        #expect(model.repositoryForNewSession(active: URL(filePath: "/code/web"))?.id == web.id)
        #expect(model.repositoryForNewSession(active: URL(filePath: "/elsewhere"))?.id == api.id)
        #expect(model.repositoryForNewSession(active: nil)?.id == api.id)
    }

    @Test func switchingToTheCurrentRepositoryChangesNothing() async throws {
        let api = try await addRepository("/code/api")
        model.beginNewSession(in: api)
        let session = try #require(model.newSession)

        model.switchNewSession(to: api)

        #expect(model.newSession === session)
    }

    @Test func aSessionStartedInAHiddenRepositoryPutsItOnShow() async throws {
        let api = try await addRepository("/code/api")
        let web = try await addRepository("/code/web")
        git.seed(branches: ["main"], at: URL(filePath: "/code/web"))
        list.setShown(web, false)
        #expect(!model.isShown(web))
        model.beginNewSession(in: web)
        let session = try #require(model.newSession)
        await session.load()
        session.editBranchName("fix")

        await model.submitNewSession()

        #expect(model.isShown(web))
        #expect(model.isShown(api))
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

    // MARK: Sessions

    @Test func aSessionIsLabelledWithItsBranch() async throws {
        let repository = try await addRepository("/code/api")
        await model.refresh([repository])

        #expect(model.worktreeLabels(of: [repository]) == [WorkspaceID(URL(filePath: "/code/api")): "main"])
    }

    /// Two repositories can each have a `main`, so with more than one on show
    /// a label says whose.
    @Test func withMoreThanOneOnShowALabelSaysWhichRepository() async throws {
        let api = try await addRepository("/code/api")
        let web = try await addRepository("/code/web")
        await model.refresh([api, web])

        let labels = model.worktreeLabels(of: [api, web])

        #expect(labels[WorkspaceID(URL(filePath: "/code/api"))] == "api/main")
        #expect(labels[WorkspaceID(URL(filePath: "/code/web"))] == "web/main")
    }

    @Test func aRepositoryNotOnShowLabelsNothing() async throws {
        let api = try await addRepository("/code/api")
        let web = try await addRepository("/code/web")
        await model.refresh([api, web])

        #expect(model.worktreeLabels(of: [api]).keys.map(\.root.name) == ["api"])
    }

    // MARK: History

    @Test func theHistoryOfEveryRepositoryOnShowIsFound() async throws {
        let api = try await addRepository("/code/api")
        let web = try await addRepository("/code/web")
        await model.refresh([api, web])

        let sources = model.historySources(of: [api, web])

        #expect(sources.map(\.key) == [PathKey(URL(filePath: "/code/api")), PathKey(URL(filePath: "/code/web"))])
        #expect(sources.first?.worktrees == [WorkspaceID(URL(filePath: "/code/api"))])
    }

    @Test func aLinkedWorktreesHistoryIsItsRepositorys() async throws {
        let repository = try await addRepository("/code/api")
        git.seed(worktrees: [
            GitWorktree(path: URL(filePath: "/code/api-feature"), checkout: .branch("feature"), isMainWorkingTree: false),
            GitWorktree(path: URL(filePath: "/code/api"), checkout: .branch("main"), isMainWorkingTree: true),
        ], at: URL(filePath: "/code/api"))
        await model.refresh([repository])

        let source = try #require(model.historySources(of: [repository]).first)

        #expect(source.key == PathKey(URL(filePath: "/code/api")))
        #expect(source.worktrees.count == 2)
        // A session whose worktree is gone is picked up in the main one.
        #expect(source.fallback == WorkspaceID(URL(filePath: "/code/api")))
    }

    @Test func aBareRepositorysFallbackIsItsFirstWorktree() async throws {
        let repository = try await addRepository("/code/bare")
        git.seed(worktrees: [
            GitWorktree(path: URL(filePath: "/code/bare/b"), checkout: .branch("b"), isMainWorkingTree: false),
            GitWorktree(path: URL(filePath: "/code/bare/main"), checkout: .branch("main"), isMainWorkingTree: false),
        ], at: URL(filePath: "/code/bare"))
        await model.refresh([repository])

        let source = try #require(model.historySources(of: [repository]).first)

        #expect(source.fallback == WorkspaceID(URL(filePath: "/code/bare/b")))
    }

    /// A bare repository has no main working tree, so what git says cannot name
    /// its history: the folder it was added as does, and does not move when a
    /// worktree is added.
    @Test func aBareRepositorysHistoryIsKeyedByItsFolder() async throws {
        let repository = try await addRepository("/code/bare")
        let worktrees = [
            GitWorktree(path: URL(filePath: "/code/bare/b"), checkout: .branch("b"), isMainWorkingTree: false),
            GitWorktree(path: URL(filePath: "/code/bare/main"), checkout: .branch("main"), isMainWorkingTree: false),
        ]
        git.seed(worktrees: worktrees, at: URL(filePath: "/code/bare"))
        await model.refresh([repository])
        let before = try #require(model.historySources(of: [repository]).first)

        git.seed(
            worktrees: worktrees + [GitWorktree(path: URL(filePath: "/code/bare/a"), checkout: .branch("a"), isMainWorkingTree: false)],
            at: URL(filePath: "/code/bare")
        )
        await model.refresh([repository])
        let after = try #require(model.historySources(of: [repository]).first)

        #expect(before.key == PathKey(URL(filePath: "/code/bare")))
        #expect(after.key == before.key)
    }

    /// Whichever worktree a session runs in, it is kept under its repository.
    @Test func aWorktreeIsKeptUnderItsRepositorysFolder() async throws {
        _ = try await addRepository("/code/api")
        git.seed(worktrees: [
            GitWorktree(path: URL(filePath: "/code/api"), checkout: .branch("main"), isMainWorkingTree: true),
            GitWorktree(path: URL(filePath: "/code/api-feature"), checkout: .branch("feature"), isMainWorkingTree: false),
        ], at: URL(filePath: "/code/api"))

        // Not read yet, as when a window restores its tabs: git is asked.
        let key = await model.historyKey(of: WorkspaceID(URL(filePath: "/code/api-feature")))

        #expect(key == PathKey(URL(filePath: "/code/api")))
        #expect(await model.historyKey(of: WorkspaceID(URL(filePath: "/code/elsewhere"))) == nil)
    }

    /// Before its worktrees are read, a repository's history is still found
    /// under its own folder; nothing in it can be resumed yet.
    @Test func aRepositoryNotYetReadIsKeyedByItsFolder() async throws {
        let repository = try await addRepository("/code/api")

        let source = try #require(model.historySources(of: [repository]).first)

        #expect(source.key == PathKey(URL(filePath: "/code/api")))
        #expect(source.worktrees.isEmpty)
        #expect(source.fallback == nil)
    }

    @Test func anUnavailableRepositoryHasNoHistoryOnShow() async throws {
        var repository = try await addRepository("/code/api")
        repository.isAvailable = false

        #expect(model.historySources(of: [repository]).isEmpty)
    }

    // MARK: Modes

    @Test func theModalCarriesTheModeItWasOpenedWith() async throws {
        let repository = try await addRepository("/code/api")

        model.beginNewSession(in: repository, mode: .plan)
        #expect(model.newSessionMode == .plan)

        model.cancelNewSession()
        model.beginNewSession(in: repository)
        #expect(model.newSessionMode == .build)
    }
}
