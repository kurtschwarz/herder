import Clients
import EditorFeature
import ExplorerFeature
import Foundation
import Observation
import SwiftData
import Storage
import Syntax
import WorkspacesFeature
import Worktrees

/// Composition root for the feature graph.
///
/// The app target builds this with live clients; tests build it with fakes. As
/// features arrive, construct their models here and hand them to `AppView`.
///
/// `@MainActor` is implicit: this target's default isolation is `MainActor`.
@Observable
public final class AppModel {
    /// Every change to the workspace list goes through here. Views read the list
    /// itself with `@Query` against the injected container.
    public let workspaces: WorkspaceStore

    /// The authoritative file and git state of the worktrees being watched.
    /// Held here rather than inside a feature because more than one pane reads
    /// it and features never import each other.
    public let worktrees: WorktreeStateStore

    /// What the sidebar shows beside the list itself.
    public let workspaceList: WorkspacesModel

    /// The file tree of the worktree selected in the sidebar.
    public let explorer: ExplorerModel

    /// The file open in the middle pane.
    public let editor: EditorModel

    /// `context` is the app's `mainContext`, the same one `@Query` reads, so a
    /// change made here shows up in the sidebar without a round trip.
    public init(
        files: any FileClient,
        bookmarks: any BookmarkClient,
        git: any GitClient,
        folderPicker: any FolderPickerClient,
        watcher: any FileWatcherClient,
        clock: any ClockClient,
        context: ModelContext
    ) {
        let workspaces = WorkspaceStore(context: context, bookmarks: bookmarks, git: git)
        self.workspaces = workspaces
        self.workspaceList = WorkspacesModel(store: workspaces, git: git, picker: folderPicker)
        let worktrees = WorktreeStateStore(files: files, git: git, watcher: watcher, clock: clock)
        self.worktrees = worktrees
        self.explorer = ExplorerModel(store: worktrees)
        self.editor = EditorModel(store: worktrees, files: files)
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
