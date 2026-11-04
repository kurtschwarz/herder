import ClientsTestSupport
import Storage
import SwiftData
import Testing

@testable import AppFeature

/// A struct suite gives every test a fresh instance, so state can't leak between
/// tests and there's no `setUp`/`tearDown` to keep in sync.
@Suite struct AppModelTests {
    let files = InMemoryFileClient()
    let bookmarks = InMemoryBookmarkClient()
    let git = StubGitClient()
    let model: AppModel

    init() throws {
        model = AppModel(
            files: files,
            bookmarks: bookmarks,
            git: git,
            folderPicker: StubFolderPickerClient(),
            context: ModelContext(try WorkspaceContainer.inMemory())
        )
    }

    @Test func buildsWithFakeClients() {
        #expect(files.files.isEmpty)
    }

    @Test func startsWithNoWorkspaces() throws {
        model.start()
        #expect(try model.workspaces.workspaces().isEmpty)
    }
}
