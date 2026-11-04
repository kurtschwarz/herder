import Clients
import ExplorerFeature
import Foundation
import Observation
import SwiftData
import Storage
import WorkspacesFeature

/// Composition root for the feature graph.
///
/// The app target builds this with live clients; tests build it with fakes. As
/// features arrive, construct their models here and hand them to `AppView`.
///
/// `@MainActor` is implicit: this target's default isolation is `MainActor`.
@Observable
public final class AppModel {
    private let files: any FileClient

    /// Every change to the workspace list goes through here. Views read the list
    /// itself with `@Query` against the injected container.
    public let workspaces: WorkspaceStore

    /// What the sidebar shows beside the list itself.
    public let workspaceList: WorkspacesModel

    /// The file tree of the worktree selected in the sidebar.
    public let explorer: ExplorerModel

    /// `context` is the app's `mainContext`, the same one `@Query` reads, so a
    /// change made here shows up in the sidebar without a round trip.
    public init(
        files: any FileClient,
        bookmarks: any BookmarkClient,
        git: any GitClient,
        folderPicker: any FolderPickerClient,
        context: ModelContext
    ) {
        self.files = files
        let workspaces = WorkspaceStore(context: context, bookmarks: bookmarks, git: git)
        self.workspaces = workspaces
        self.workspaceList = WorkspacesModel(store: workspaces, git: git, picker: folderPicker)
        self.explorer = ExplorerModel(files: files)
    }

    /// Opens the add-workspace modal. Here rather than on the sidebar because a
    /// menu command, not just the sidebar's button, asks for it.
    public func beginAddingWorkspace() {
        workspaceList.beginAdding()
    }

    /// Takes access to every workspace folder. Called at launch, before any view
    /// exists: a workspace must be reachable before anything can render it.
    public func start() {
        do {
            try workspaces.open()
        } catch {
            // Nothing here is recoverable by the app, and the per-workspace
            // failures are already reported as unavailable workspaces.
            assertionFailure("Could not open workspaces: \(error)")
        }
    }

    /// Hands back every folder the sandbox is holding open. Balances `start()`.
    public func stop() {
        workspaces.access.endAll()
    }
}
