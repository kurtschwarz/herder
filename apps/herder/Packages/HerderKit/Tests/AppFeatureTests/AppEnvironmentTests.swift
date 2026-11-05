import Storage
import TestSupport
import Testing

@testable import AppFeature

/// A struct suite gives every test a fresh instance, so state can't leak between
/// tests and there's no `setUp`/`tearDown` to keep in sync.
@Suite struct AppEnvironmentTests {
    let files = InMemoryFileClient()
    let bookmarks = InMemoryBookmarkClient()
    let git = StubGitClient()
    let environment: AppEnvironment

    init() throws {
        environment = AppEnvironment(
            files: files,
            bookmarks: bookmarks,
            git: git,
            folderPicker: StubFolderPickerClient(),
            watcher: StubFileWatcherClient(),
            clock: VirtualClockClient(),
            container: try WorkspaceContainer.inMemory()
        )
    }

    @Test func buildsWithFakeClients() {
        #expect(files.files.isEmpty)
    }

    @Test func startsWithNoWorkspaces() throws {
        environment.start()
        #expect(try environment.workspaces.workspaces().isEmpty)
    }
}
