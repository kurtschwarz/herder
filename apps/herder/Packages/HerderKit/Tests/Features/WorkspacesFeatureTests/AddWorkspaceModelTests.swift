import Core
import Foundation
import Storage
import SwiftData
import TestSupport
import Testing

@testable import WorkspacesFeature

@Suite struct AddWorkspaceModelTests {
    let bookmarks = InMemoryBookmarkClient()
    let git = StubGitClient()
    let picker = StubFolderPickerClient()
    let store: SwiftDataRepositoryStore
    let model: AddWorkspaceModel

    init() throws {
        let container = try WorkspaceContainer.inMemory()
        store = SwiftDataRepositoryStore(context: ModelContext(container), bookmarks: bookmarks, git: git)
        model = AddWorkspaceModel(store: store, picker: picker)
    }

    @discardableResult
    func repository(_ path: String, kind: GitRepositoryKind = .mainWorkingTree) -> URL {
        let url = URL(filePath: path)
        git.seed(url, kind)
        return url
    }

    @Test func nothingCanBeAddedBeforeAFolderIsPicked() async {
        #expect(!model.canAdd)
        #expect(await !model.submit())
    }

    @Test func pickingARepositoryFillsTheNameAndEnablesAdd() async {
        picker.script(repository("/code/api"))

        await model.browse()

        #expect(model.folder == URL(filePath: "/code/api"))
        #expect(model.name == "api")
        #expect(model.refusal == nil)
        #expect(model.canAdd)
    }

    @Test func aBareRepositoryNameLosesItsGitSuffix() async {
        picker.script(repository("/code/api.git", kind: .bare))
        await model.browse()
        #expect(model.name == "api")
    }

    @Test func cancellingThePickerChangesNothing() async {
        picker.script(repository("/code/api"))
        await model.browse()

        await model.browse()

        #expect(model.folder == URL(filePath: "/code/api"))
        #expect(model.canAdd)
    }

    @Test func aFolderThatIsNotARepositoryIsRefusedAtOnce() async {
        picker.script(URL(filePath: "/code/notes"))

        await model.browse()

        #expect(model.refusal == .notARepository)
        #expect(!model.canAdd)
        #expect(model.name == "")
    }

    @Test func aFolderAlreadyInTheSidebarIsRefused() async throws {
        let url = repository("/code/api")
        try await store.add(url: url)
        picker.script(url)

        await model.browse()

        #expect(model.refusal == .alreadyOpen)
        #expect(!model.canAdd)
    }

    @Test func aLinkedWorktreeNamesItsRepository() async {
        let main = URL(filePath: "/code/api")
        picker.script(repository("/code/feature", kind: .linkedWorktree(mainRepository: main)))

        await model.browse()

        #expect(model.refusal == .linkedWorktree(mainRepository: main))
        #expect(!model.canAdd)
    }

    @Test func choosingTheMainRepositoryReopensThePickerThere() async {
        let main = repository("/code/api")
        picker.script(repository("/code/feature", kind: .linkedWorktree(mainRepository: main)))
        picker.script(main)
        await model.browse()

        await model.chooseMainRepository()

        #expect(picker.starts == [nil, main])
        #expect(model.folder == main)
        #expect(model.refusal == nil)
        #expect(model.canAdd)
    }

    @Test func choosingTheMainRepositoryDoesNothingForOtherRefusals() async {
        picker.script(URL(filePath: "/code/notes"))
        await model.browse()

        await model.chooseMainRepository()

        #expect(picker.requests == 1)
    }

    @Test func aNameTheUserTypedSurvivesPickingAnotherFolder() async {
        picker.script(repository("/code/api"))
        picker.script(repository("/code/web"))
        await model.browse()

        model.editName("Gateway")
        await model.browse()

        #expect(model.folder == URL(filePath: "/code/web"))
        #expect(model.name == "Gateway")
    }

    @Test func aNameTheUserDidNotTypeFollowsTheFolder() async {
        picker.script(repository("/code/api"))
        picker.script(repository("/code/web"))

        await model.browse()
        await model.browse()

        #expect(model.name == "web")
    }

    @Test func submittingAddsTheWorkspaceWithTheTypedName() async throws {
        picker.script(repository("/code/api"))
        await model.browse()
        model.editName("  Gateway ")

        #expect(await model.submit())

        let added = try #require(try store.workspaces().first)
        #expect(added.name == "Gateway")
        #expect(added.path == "/code/api")
    }

    @Test func aBlankNameFallsBackToTheFolderName() async throws {
        picker.script(repository("/code/api"))
        await model.browse()
        model.editName("   ")

        #expect(await model.submit())

        #expect(try store.workspaces().first?.name == "api")
    }

    @Test func aFolderThatChangedAfterThePickIsRefusedOnSubmit() async throws {
        let url = repository("/code/api")
        picker.script(url)
        await model.browse()
        git.seed(url, .notARepository)

        #expect(await !model.submit())

        #expect(model.refusal == .notARepository)
        #expect(!model.canAdd)
        #expect(try store.workspaces().isEmpty)
    }
}
