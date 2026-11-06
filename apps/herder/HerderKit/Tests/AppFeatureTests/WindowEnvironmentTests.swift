import Core
import Foundation
import Services
import Synchronization
import TestSupport
import Testing

@testable import AppFeature

/// What one window owns.
///
/// Per window, which is the point: the models used to be built once for the
/// app, so a click in one window changed the editor in every other, and a modal
/// in one disabled them all. Two windows on different checkouts of one
/// repository is what Herder is for.
@Suite @MainActor struct WindowEnvironmentTests {
    let files = InMemoryFileClient()
    let environment: AppEnvironment

    private let api = URL(filePath: "/code/api")
    private let web = URL(filePath: "/code/web")

    init() {
        environment = AppEnvironment(
            files: files,
            bookmarks: InMemoryBookmarkClient(),
            git: StubGitClient(),
            folderPicker: StubFolderPickerClient(),
            watcher: StubFileWatcherClient(),
            clock: VirtualClockClient(),
            persistence: PersistenceStack.temporary()
        )
        for folder in [api, web] {
            files.seed(folder.appending(path: "a.txt").path(percentEncoded: false), "\(folder.lastPathComponent) a")
            files.seed(
                children: [DirectoryEntry(url: folder.appending(path: "a.txt"), isDirectory: false)],
                of: folder
            )
        }
    }

    // MARK: - Which workspace

    @Test func aNewWindowShowsNothing() {
        #expect(environment.makeWindow().activeWorkspaceID == nil)
    }

    @Test func activatingShows() {
        let window = environment.makeWindow()
        window.activate(WorkspaceID(api))
        #expect(window.activeWorkspaceID == WorkspaceID(api))
    }

    @Test func activatingNothingClears() {
        let window = environment.makeWindow()
        window.activate(WorkspaceID(api))
        window.activate(nil)
        #expect(window.activeWorkspaceID == nil)
    }

    /// `withObservationTracking`'s handler is `@Sendable`, so the count cannot
    /// be a captured `var`. A `Mutex` rather than an `@unchecked Sendable` box:
    /// the compiler's objection is reasonable and cheap to satisfy.
    private func changeCount(_ body: (WindowEnvironment) -> Void, on window: WindowEnvironment) -> Int {
        let changes = Mutex(0)
        withObservationTracking {
            _ = window.activeWorkspaceID
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        body(window)
        return changes.withLock { $0 }
    }

    /// Switching drives the work of opening a workspace, so asking for what is
    /// already showing must not look like a change.
    @Test func activatingWhatIsAlreadyShowingIsNotAChange() {
        let window = environment.makeWindow()
        window.activate(WorkspaceID(api))
        #expect(changeCount({ $0.activate(WorkspaceID(api)) }, on: window) == 0)
    }

    @Test func switchingIsNoticed() {
        let window = environment.makeWindow()
        window.activate(WorkspaceID(api))
        #expect(changeCount({ $0.activate(WorkspaceID(web)) }, on: window) == 1)
    }

    @Test func twoWindowsShowDifferentWorkspaces() {
        let first = environment.makeWindow()
        let second = environment.makeWindow()

        first.activate(WorkspaceID(api))
        second.activate(WorkspaceID(web))

        #expect(first.activeWorkspaceID == WorkspaceID(api))
        #expect(second.activeWorkspaceID == WorkspaceID(web))
    }

    // MARK: - Which panes

    @Test func windowsDoNotShareModels() {
        let first = environment.makeWindow()
        let second = environment.makeWindow()

        #expect(first.editor !== second.editor)
        #expect(first.fileTree !== second.fileTree)
        #expect(first.repositoryList !== second.repositoryList)
    }

    /// The defect this exists to fix: a file chosen in one window used to
    /// open in the editor of every window.
    @Test func openingAFileInOneWindowLeavesTheOthersEditorAlone() async throws {
        let first = environment.makeWindow()
        let second = environment.makeWindow()
        first.activate(WorkspaceID(api))
        second.activate(WorkspaceID(web))
        await first.showActiveWorkspace()
        await second.showActiveWorkspace()

        first.fileTree.select(api.appending(path: "a.txt"))
        await first.openSelectedFile()

        #expect(first.editor.file == api.appending(path: "a.txt"))
        #expect(second.editor.file == nil)
    }

    /// A modal gates its own window's keyboard, and no one else's.
    @Test func aModalInOneWindowDoesNotGateTheOthers() {
        let first = environment.makeWindow()
        let second = environment.makeWindow()

        first.beginAddingRepository()

        #expect(first.repositoryList.isModalPresented)
        #expect(!second.repositoryList.isModalPresented)
    }

    /// The workspace is the app's, not the window's: two windows on one
    /// checkout read one set of listings.
    @Test func windowsOnTheSameCheckoutShareItsWorkspace() async throws {
        let first = environment.makeWindow()
        let second = environment.makeWindow()
        first.activate(WorkspaceID(api))
        second.activate(WorkspaceID(api))
        await first.showActiveWorkspace()
        await second.showActiveWorkspace()

        #expect(first.activeWorkspace === second.activeWorkspace)
        #expect(first.activeWorkspace != nil)
    }
}
