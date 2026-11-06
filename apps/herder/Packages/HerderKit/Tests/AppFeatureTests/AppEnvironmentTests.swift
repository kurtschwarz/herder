import Core
import Services
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
            persistence: PersistenceStack.temporary()
        )
    }

    @Test func buildsWithFakeClients() {
        #expect(files.files.isEmpty)
    }

    @Test func startsWithNoRepositories() async throws {
        await environment.start()
        #expect(environment.repositories.repositories.isEmpty)
    }

    @Test func aFirstLaunchHasNoWorkspaceToRestore() async {
        #expect(await environment.restoredWorkspace() == nil)
    }

    /// For a window whose scene storage is empty, which is every window after
    /// a quit that closed them.
    @Test func theLastWorkspaceShownComesBack() async throws {
        let id = WorkspaceID(PathKey(canonical: "/code/api"))
        try await environment.state.save(
            AppSnapshot(lastActiveWorkspace: id),
            forKey: AppSnapshot.persistenceKey
        )

        #expect(await environment.restoredWorkspace() == id)
    }

    /// Asking is also starting: a window's restore task may run before the
    /// task that starts the app, and the folder access it needs is taken there.
    @Test func askingForTheWorkspaceStartsTheApp() async throws {
        let id = WorkspaceID(PathKey(canonical: "/code/api"))
        try await environment.state.save(
            AppSnapshot(openWorkspaces: [id], lastActiveWorkspace: id),
            forKey: AppSnapshot.persistenceKey
        )

        _ = await environment.restoredWorkspace()

        #expect(environment.worktrees.workspace(for: id) != nil)
    }
}
