import Core
import EditorFeature
import ExplorerFeature
import Foundation
import Observation
import Services
import Storage
import SwiftData
import WorkspacesFeature

/// Composition root.
///
/// The only place in the codebase that names a concrete service type: ``init()``
/// builds the live ones, and the designated initializer takes whatever it is
/// given so tests and previews can pass fakes. As features arrive, construct
/// their models here and hand them to `AppView`.
///
/// This is why the app target is one file: everything that would otherwise be
/// wired up in `@main` is wired up here instead, where SwiftPM picks up new
/// files without the Xcode project having to be regenerated.
///
/// `@MainActor` is implicit: this target's default isolation is `MainActor`.
@Observable
public final class AppEnvironment {
    /// The SwiftData container the whole app shares. Held so the scene can hand
    /// it to `.modelContainer(_:)`, which is what puts it in reach of `@Query`.
    public let container: ModelContainer

    /// Where the app keeps its own state: open workspaces, tabs, expanded
    /// folders. App-scoped, because one store serves every window.
    ///
    /// Nothing reads it yet. It is built here from Phase 3 so that Phase 4 has
    /// something to restore from, and so the construction is proven before
    /// anything depends on it.
    public let state: any StateStore

    /// Every change to the workspace list goes through here. Views read the list
    /// itself with `@Query` against the same container.
    public let workspaces: SwiftDataRepositoryStore

    /// The authoritative file and git state of the worktrees being watched.
    /// Held here rather than inside a feature because more than one pane reads
    /// it and features never import each other.
    public let worktrees: WorkspaceRegistry

    /// What the sidebar shows beside the list itself.
    public let workspaceList: WorkspacesModel

    /// The file tree of the worktree selected in the sidebar.
    public let explorer: ExplorerModel

    /// The file open in the middle pane.
    public let editor: EditorModel

    /// The live app: every service is the real one.
    ///
    /// There is no app without its workspaces, and nothing useful to fall back
    /// to, so a container that cannot be opened is fatal: an in-memory store
    /// would silently throw away everything the user adds.
    public convenience init() {
        let container: ModelContainer
        do {
            container = try WorkspaceContainer.live()
        } catch {
            fatalError("Could not open the workspace store: \(error)")
        }

        self.init(
            files: LiveFileClient(),
            bookmarks: LiveBookmarkClient(),
            git: LiveGitClient(),
            folderPicker: LiveFolderPickerClient(),
            watcher: LiveFileWatcherClient(),
            clock: LiveClockClient(),
            container: container
        )
    }

    /// Takes every service, so tests and previews can pass fakes.
    ///
    /// The store writes through `container.mainContext`, the same context
    /// `@Query` reads, so a change made here shows up in the sidebar without a
    /// round trip.
    ///
    /// `highlighter` is named here rather than defaulted inside the editor
    /// because this is the only module allowed to know a concrete service type.
    public init(
        files: any FileClient,
        bookmarks: any BookmarkClient,
        git: any GitClient,
        folderPicker: any FolderPickerClient,
        watcher: any FileWatcherClient,
        clock: any ClockClient,
        container: ModelContainer,
        highlighter: any SyntaxHighlighter = TreeSitterHighlighter()
    ) {
        self.container = container
        self.state = SwiftDataStateStore(container: container)
        let workspaces = SwiftDataRepositoryStore(context: container.mainContext, bookmarks: bookmarks, git: git)
        self.workspaces = workspaces
        self.workspaceList = WorkspacesModel(store: workspaces, git: git, picker: folderPicker)
        let worktrees = WorkspaceRegistry(files: files, git: git, watcher: watcher, clock: clock)
        self.worktrees = worktrees
        self.explorer = ExplorerModel(store: worktrees)
        self.editor = EditorModel(store: worktrees, files: files, highlighter: highlighter)
    }

    /// Opens the add-workspace modal. Here rather than on the sidebar because a
    /// menu command, not just the sidebar's button, asks for it.
    public func beginAddingWorkspace() {
        workspaceList.beginAdding()
    }

    /// Takes access to every workspace folder. Called at launch, before any view
    /// exists: a workspace must be reachable before anything can render it.
    public func start() {
        // Compiling the editor's grammars takes a few hundred milliseconds in
        // total, and all of it is paid the first time a file of each language
        // is opened unless it is paid here instead. Detached and unawaited:
        // nothing waits on it, and a reader who opens a file before it finishes
        // simply gets the colour a moment later.
        Task.detached { await TreeSitterHighlighter.warmUp() }

        do {
            try workspaces.open()
        } catch {
            // Nothing here is recoverable by the app, and the per-workspace
            // failures are already reported as unavailable workspaces.
            assertionFailure("Could not open workspaces: \(error)")
        }
    }

    /// Hands back every folder the sandbox is holding open, and stops watching
    /// for changes. Balances `start()`.
    public func stop() {
        worktrees.stop()
        workspaces.access.endAll()
    }
}
