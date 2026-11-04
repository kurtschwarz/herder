import Clients
import ClientsTestSupport
import Foundation
import Storage
import SwiftData
import Testing

@testable import WorkspacesFeature

@Suite struct WorkspacesModelTests {
    let bookmarks = InMemoryBookmarkClient()
    let git = StubGitClient()
    let container: ModelContainer
    let store: WorkspaceStore
    let picker = StubFolderPickerClient()
    let defaults: UserDefaults
    let suite: String
    let model: WorkspacesModel

    init() throws {
        container = try WorkspaceContainer.inMemory()
        store = WorkspaceStore(context: ModelContext(container), bookmarks: bookmarks, git: git)
        suite = "WorkspacesModelTests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        model = WorkspacesModel(store: store, git: git, picker: picker, defaults: defaults)
    }

    func addWorkspace(_ path: String) async throws -> Workspace {
        let url = URL(filePath: path)
        git.seed(url, .mainWorkingTree)
        git.seed(worktrees: [GitWorktree(path: url, checkout: .branch("main"), isMainWorkingTree: true)], at: url)
        return try await store.add(url: url)
    }

    @Test func refreshReadsTheWorktreesOfOpenWorkspaces() async throws {
        let workspace = try await addWorkspace("/code/api")

        await model.refresh([workspace])

        #expect(model.listings[workspace.id] == .loaded([
            GitWorktree(path: URL(filePath: "/code/api"), checkout: .branch("main"), isMainWorkingTree: true)
        ]))
    }

    @Test func aFolderThatCannotBeReadIsNotAnEmptyRepository() async throws {
        let workspace = try await addWorkspace("/code/api")
        git.seedUnreadable(URL(filePath: "/code/api"))

        await model.refresh([workspace])

        #expect(model.listings[workspace.id] == .unreadable)
    }

    @Test func anUnavailableWorkspaceIsNeitherReadNorExpanded() async throws {
        let workspace = try await addWorkspace("/code/api")
        workspace.isAvailable = false

        await model.refresh([workspace])

        #expect(model.listings[workspace.id] == nil)
        #expect(!model.isExpanded(workspace))
    }

    @Test func workspacesStartExpanded() async throws {
        let workspace = try await addWorkspace("/code/api")
        #expect(model.isExpanded(workspace))
    }

    @Test func aCollapsedWorkspaceIsNotRead() async throws {
        let workspace = try await addWorkspace("/code/api")

        await model.toggle(workspace)
        await model.refresh([workspace])

        #expect(!model.isExpanded(workspace))
        #expect(model.listings[workspace.id] == nil)
    }

    @Test func expandingAgainReadsTheWorktrees() async throws {
        let workspace = try await addWorkspace("/code/api")

        await model.toggle(workspace)
        await model.toggle(workspace)

        #expect(model.isExpanded(workspace))
        #expect(model.listings[workspace.id] != nil)
    }

    @Test func collapsingSurvivesALaunch() async throws {
        let workspace = try await addWorkspace("/code/api")
        await model.toggle(workspace)

        let next = WorkspacesModel(store: store, git: git, picker: picker, defaults: defaults)

        #expect(!next.isExpanded(workspace))
    }

    @Test func removingForgetsTheWorkspaceAndItsState() async throws {
        let workspace = try await addWorkspace("/code/api")
        let id = workspace.id
        await model.refresh([workspace])
        await model.toggle(workspace)

        model.remove(workspace)

        #expect(try store.workspaces().isEmpty)
        #expect(model.listings[id] == nil)
        #expect(!model.collapsed.contains(id))
    }

    @Test func committingARenameEndsEditingAndSavesTheName() async throws {
        let workspace = try await addWorkspace("/code/api")
        model.renaming = workspace.id

        model.commitRename(workspace, to: "Gateway")

        #expect(model.renaming == nil)
        #expect(workspace.name == "Gateway")
    }

    @Test func committingABlankRenameKeepsTheName() async throws {
        let workspace = try await addWorkspace("/code/api")
        model.renaming = workspace.id

        model.commitRename(workspace, to: "")

        #expect(model.renaming == nil)
        #expect(workspace.name == "api")
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

    @Test func submittingClosesTheModalOnceTheWorkspaceIsAdded() async throws {
        let url = URL(filePath: "/code/api")
        git.seed(url, .mainWorkingTree)
        picker.script(url)
        model.beginAdding()
        await model.adding?.browse()

        await model.submitAdding()

        #expect(model.adding == nil)
        #expect(try store.workspaces().count == 1)
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

    @Test func aNewSessionOpensForAnAvailableWorkspace() async throws {
        let workspace = try await addWorkspace("/code/api")

        model.beginNewSession(in: workspace)

        #expect(model.newSession?.workspaceName == "api")
        #expect(model.isModalPresented)
    }

    @Test func anUnavailableWorkspaceCannotStartASession() async throws {
        let workspace = try await addWorkspace("/code/api")
        workspace.isAvailable = false

        model.beginNewSession(in: workspace)

        #expect(model.newSession == nil)
    }

    @Test func onlyOneModalAtATime() async throws {
        let workspace = try await addWorkspace("/code/api")
        model.beginAdding()

        model.beginNewSession(in: workspace)
        #expect(model.newSession == nil)

        model.cancelAdding()
        model.beginNewSession(in: workspace)
        model.beginAdding()
        #expect(model.adding == nil)
    }

    @Test func creatingAWorktreeClosesTheModalAndShowsIt() async throws {
        let workspace = try await addWorkspace("/code/api")
        let url = URL(filePath: "/code/api")
        git.seed(branches: ["main"], at: url)
        model.beginNewSession(in: workspace)
        let session = try #require(model.newSession)
        await session.load()
        session.editBranchName("fix")
        // What git would now list, once the worktree exists.
        let created = GitWorktree(path: url.appending(path: "fix"), checkout: .branch("fix"), isMainWorkingTree: false)

        git.seed(worktrees: [created], at: url)
        await model.submitNewSession()

        #expect(model.newSession == nil)
        #expect(git.addedWorktrees.count == 1)
        #expect(model.listings[workspace.id] == .loaded([created]))
    }

    @Test func aRefusedCreateLeavesTheModalUp() async throws {
        let workspace = try await addWorkspace("/code/api")
        git.seed(branches: ["main"], at: URL(filePath: "/code/api"))
        git.failAddingWorktrees(with: "no")
        model.beginNewSession(in: workspace)
        let session = try #require(model.newSession)
        await session.load()
        session.editBranchName("fix")

        await model.submitNewSession()

        #expect(model.newSession != nil)
        #expect(session.failure == "no")
    }
}
