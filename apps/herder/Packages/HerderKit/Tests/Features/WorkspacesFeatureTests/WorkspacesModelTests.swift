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
    let defaults: UserDefaults
    let suite: String
    let model: WorkspacesModel

    init() throws {
        container = try WorkspaceContainer.inMemory()
        store = WorkspaceStore(context: ModelContext(container), bookmarks: bookmarks, git: git)
        suite = "WorkspacesModelTests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        model = WorkspacesModel(store: store, git: git, defaults: defaults)
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

        let next = WorkspacesModel(store: store, git: git, defaults: defaults)

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
}
