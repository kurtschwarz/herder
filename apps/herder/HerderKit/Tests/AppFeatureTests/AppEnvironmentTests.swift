import Core
import Foundation
import Services
import TestSupport
import Testing

@testable import AppFeature

/// A struct suite gives every test a fresh instance, so state can't leak between
/// tests and there's no `setUp`/`tearDown` to keep in sync.
@Suite @MainActor struct AppEnvironmentTests {
    let files = InMemoryFileClient()
    let bookmarks = InMemoryBookmarkClient()
    let git = StubGitClient()
    let persistence = PersistenceStack.temporary()
    let environment: AppEnvironment

    private let api = WorkspaceID(PathKey(canonical: "/code/api"))
    private let web = WorkspaceID(PathKey(canonical: "/code/web"))

    init() throws {
        environment = AppEnvironment(
            files: files,
            bookmarks: bookmarks,
            git: git,
            folderPicker: StubFolderPickerClient(),
            watcher: StubFileWatcherClient(),
            clock: VirtualClockClient(),
            persistence: persistence
        )
    }

    /// The same files on disk under a second app: what a relaunch is.
    private func relaunched() -> AppEnvironment {
        AppEnvironment(
            files: files,
            bookmarks: bookmarks,
            git: git,
            folderPicker: StubFolderPickerClient(),
            watcher: StubFileWatcherClient(),
            clock: VirtualClockClient(),
            persistence: persistence
        )
    }

    /// A window with `workspaces` open and the last of them showing, saved.
    private func usedWindow(
        in environment: AppEnvironment,
        showing workspaces: WorkspaceID...
    ) async -> WindowEnvironment {
        let window = await environment.claimWindow(id: nil)
        for workspace in workspaces { window.activate(workspace) }
        await window.flushSaves()
        return window
    }

    @Test func buildsWithFakeClients() {
        #expect(files.files.isEmpty)
    }

    @Test func startingEndsLeftoverAgentsOnce() async throws {
        let leftovers = StubLeftoverAgentClient()
        let environment = AppEnvironment(
            files: files,
            bookmarks: bookmarks,
            git: git,
            folderPicker: StubFolderPickerClient(),
            watcher: StubFileWatcherClient(),
            clock: VirtualClockClient(),
            persistence: persistence,
            leftovers: leftovers
        )
        await environment.start()
        await environment.start()
        // Unawaited by `start`, so given a moment.
        for _ in 0..<100 where leftovers.sweeps == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(leftovers.sweeps == 1)
    }

    private func environment(opencode: StubOpencodeIntegrationClient, bundle: String) -> AppEnvironment {
        AppEnvironment(
            files: files,
            bookmarks: bookmarks,
            git: git,
            folderPicker: StubFolderPickerClient(),
            watcher: StubFileWatcherClient(),
            clock: VirtualClockClient(),
            persistence: persistence,
            opencode: opencode,
            bundle: URL(filePath: bundle, directoryHint: .isDirectory)
        )
    }

    @Test func startingFromApplicationsSetsUpOpencodeOnce() async {
        let opencode = StubOpencodeIntegrationClient()
        let environment = environment(opencode: opencode, bundle: "/Applications/Herder.app")
        await environment.start()
        await environment.start()
        #expect(opencode.installs == 1)
    }

    @Test func startingFromTheDiskImageLeavesOpencodeAlone() async {
        let opencode = StubOpencodeIntegrationClient()
        await environment(opencode: opencode, bundle: "/Volumes/Herder/Herder.app").start()
        #expect(opencode.installs == 0)
    }

    @Test func startsWithNoRepositories() async throws {
        await environment.start()
        #expect(environment.repositories.repositories.isEmpty)
    }

    // MARK: - Claiming a window

    @Test func aFirstLaunchGivesABlankWindow() async {
        let window = await environment.claimWindow(id: nil)

        #expect(window.activeWorkspaceID == nil)
        #expect(window.openWorkspaces.isEmpty)
    }

    @Test func aWindowKeepsTheIdentityTheSystemKept() async {
        let id = UUID()

        #expect(await environment.claimWindow(id: id).id == id)
    }

    @Test func aWindowComesBackAsItWas() async {
        let first = await usedWindow(in: environment, showing: api, web)

        let window = await relaunched().claimWindow(id: first.id)

        #expect(window.id == first.id)
        #expect(window.activeWorkspaceID == web)
        #expect(window.openWorkspaces == [api, web])
    }

    /// The scene storage is lost when the system does not restore the scene,
    /// which is every window after a quit that closed them.
    @Test func aWindowWithoutAnIdentityAdoptsTheOneUsedLast() async {
        let first = await usedWindow(in: environment, showing: api)

        let window = await relaunched().claimWindow(id: nil)

        #expect(window.id == first.id)
        #expect(window.activeWorkspaceID == api)
    }

    @Test func theMostRecentlyUsedIsTheOneAdopted() async {
        let older = await usedWindow(in: environment, showing: api)
        let newer = await usedWindow(in: environment, showing: web)
        // Using the older one again makes it the latest.
        older.activate(WorkspaceID(PathKey(canonical: "/code/tools")))
        await older.flushSaves()
        _ = newer

        let window = await relaunched().claimWindow(id: nil)

        #expect(window.id == older.id)
    }

    /// Two windows asking at once must not both become the same window.
    @Test func twoWindowsDoNotAdoptTheSameSnapshot() async {
        let first = await usedWindow(in: environment, showing: api)
        let app = relaunched()

        async let one = app.claimWindow(id: nil)
        async let two = app.claimWindow(id: nil)
        let (a, b) = await (one, two)

        #expect(a.id != b.id)
        #expect([a.id, b.id].contains(first.id))
    }

    /// ⌘N: a blank slate, even though there is state to adopt.
    @Test func anotherWindowOpenMeansABlankSlate() async {
        _ = await usedWindow(in: environment, showing: api)
        let app = relaunched()
        _ = await app.claimWindow(id: nil)

        let second = await app.claimWindow(id: nil)

        #expect(second.activeWorkspaceID == nil)
        #expect(second.openWorkspaces.isEmpty)
    }

    // MARK: - Closing

    @Test func closingAWindowForgetsIt() async {
        let closing = await usedWindow(in: environment, showing: api)
        let staying = await usedWindow(in: environment, showing: web)

        await environment.close(closing)

        #expect(await environment.windows.load(closing.id) == nil)
        #expect(await environment.windows.load(staying.id) != nil)
    }

    /// Closing every window must not read as the app having forgotten
    /// everything on the next launch.
    @Test func closingTheLastWindowKeepsItForTheNextOne() async {
        let only = await usedWindow(in: environment, showing: api)
        await environment.close(only)

        let window = await environment.claimWindow(id: nil)

        #expect(window.id == only.id)
        #expect(window.activeWorkspaceID == api)
    }

    @Test func aWindowNothingWasDoneInLeavesNoSnapshot() async {
        let blank = await environment.claimWindow(id: nil)
        await blank.flushSaves()

        #expect(await environment.windows.index().isEmpty)
    }

    /// The app quitting is not a window closing: `stop()` must leave what each
    /// window had, for the next launch.
    @Test func quittingKeepsEveryWindow() async {
        let window = await usedWindow(in: environment, showing: api)

        environment.stop()

        #expect(await environment.windows.load(window.id) != nil)
    }

    // MARK: - What a window lists

    private func adopt(_ path: String, in window: WindowEnvironment) async throws -> Repository {
        let url = URL(filePath: path)
        git.seed(url, .mainWorkingTree)
        return try await window.repositories.add(url: url)
    }

    /// The feature: a new window starts with its own, empty sidebar and can add
    /// completely different repositories.
    @Test func aNewWindowHasItsOwnSidebar() async throws {
        let first = await environment.claimWindow(id: nil)
        _ = try await adopt("/code/api", in: first)

        let second = await environment.claimWindow(id: nil)
        _ = try await adopt("/code/web", in: second)

        #expect(first.repositories.repositories.map(\.name) == ["api"])
        #expect(second.repositories.repositories.map(\.name) == ["web"])
    }

    /// A window with only a sidebar is worth remembering.
    @Test func addingARepositoryIsSavedWithTheWindow() async throws {
        let window = await environment.claimWindow(id: nil)
        let added = try await adopt("/code/api", in: window)
        await window.flushSaves()

        #expect(await environment.windows.load(window.id)?.repositories == [RepositoryMembership(repositoryID: added.id)])
    }

    @Test func eachWindowComesBackWithItsOwnSidebar() async throws {
        let first = await environment.claimWindow(id: nil)
        let api = try await adopt("/code/api", in: first)
        first.repositories.setCollapsed(api, true)
        let second = await environment.claimWindow(id: nil)
        _ = try await adopt("/code/web", in: second)
        await first.flushSaves()
        await second.flushSaves()

        let app = relaunched()
        let one = await app.claimWindow(id: first.id)
        let two = await app.claimWindow(id: second.id)

        #expect(one.repositories.repositories.map(\.name) == ["api"])
        #expect(one.repositories.isCollapsed(api))
        #expect(two.repositories.repositories.map(\.name) == ["web"])
    }

    /// Both windows list one folder: one record, one bookmark.
    @Test func windowsListingOneFolderShareItsRecord() async throws {
        let first = await environment.claimWindow(id: nil)
        let second = await environment.claimWindow(id: nil)

        let a = try await adopt("/code/api", in: first)
        let b = try await adopt("/code/api", in: second)

        #expect(a.id == b.id)
        #expect(environment.repositories.repositories.count == 1)
    }

    /// Closing a window forgets what it listed, not the folders: they are still
    /// adopted, and picking one again joins the same record.
    @Test func closingAWindowKeepsTheRepositoriesItListed() async throws {
        let closing = await environment.claimWindow(id: nil)
        let added = try await adopt("/code/api", in: closing)
        await closing.flushSaves()
        let other = await environment.claimWindow(id: nil)
        _ = try await adopt("/code/web", in: other)
        await other.flushSaves()

        await environment.close(closing)

        #expect(environment.repositories.repositories.map(\.id).contains(added.id))
        #expect(await environment.windows.load(closing.id) == nil)
    }

    /// Windows and repositories share the app snapshot, and neither may write
    /// the other away.
    @Test func theWindowIndexAndTheRepositoriesCoexist() async throws {
        let window = await environment.claimWindow(id: nil)
        _ = try await adopt("/code/api", in: window)
        await window.flushSaves()

        let snapshot = try await persistence.state.load(AppSnapshot.self, forKey: AppSnapshot.persistenceKey)

        #expect(snapshot?.repositories.map(\.name) == ["api"])
        #expect(snapshot?.windows == [window.id])
    }

    // MARK: - What a window holds

    @Test func closingAWindowLetsGoOfWhatOnlyItHeld() async {
        let closing = await usedWindow(in: environment, showing: api)
        await closing.showActiveWorkspace()
        #expect(environment.worktrees.workspace(for: api) != nil)

        await environment.close(closing)

        #expect(environment.worktrees.workspace(for: api) == nil)
    }

    @Test func closingAWindowKeepsWhatAnotherStillHolds() async {
        let closing = await usedWindow(in: environment, showing: api)
        let staying = await usedWindow(in: environment, showing: api)
        await closing.showActiveWorkspace()
        await staying.showActiveWorkspace()

        await environment.close(closing)

        #expect(environment.worktrees.workspace(for: api) != nil)
    }

    /// Restoring a window brings back every workspace it held, not only the
    /// one it shows.
    @Test func aRestoredWindowReopensWhatItHeld() async {
        let first = await usedWindow(in: environment, showing: api, web)
        let app = relaunched()

        let window = await app.claimWindow(id: first.id)
        await window.showActiveWorkspace()
        await window.reopenHeldWorkspaces()

        #expect(app.worktrees.workspace(for: api) != nil)
        #expect(app.worktrees.workspace(for: web) != nil)
    }

    /// A worktree that went away is forgotten by its window, and the workspace
    /// with it unless someone else holds it.
    @Test func forgettingAWorkspaceClearsItFromTheWindow() async {
        let window = await usedWindow(in: environment, showing: api, web)
        await window.showActiveWorkspace()

        await window.forget(web)
        await window.flushSaves()

        #expect(window.activeWorkspaceID == nil)
        #expect(window.openWorkspaces == [api])
        #expect(await environment.windows.load(window.id)?.openWorkspaces == [api])
    }
}
