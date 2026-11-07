import AgentSessionsFeature
import Core
import EditorFeature
import FileTreeFeature
import Foundation
import Observation
import RepositoriesFeature
import TerminalFeature

/// Everything one window owns: which workspace it is showing, and the models
/// behind its panes.
///
/// Per window, not per app. Two windows showing different checkouts of the same
/// repository is the thing Herder is for, so neither "active" nor the file open
/// in the editor can be a single fact held somewhere central. They were, once:
/// one editor and one file tree for the whole app, so a click in one window
/// changed the other.
///
/// What stays shared is what must be singular: the repository list, the folder
/// access behind it, and the ``WorkspaceRegistry`` that is the one source of
/// truth for a worktree's files and git state. Two windows on one checkout read
/// one ``Workspace``.
///
/// Switching is the whole of what ``activate(_:)`` does. It sets an id and
/// nothing else: no workspace is torn down, no documents are closed, no agent
/// is stopped. What the window shows is resolved from the id.
@Observable
final class WindowEnvironment {
    /// Names this window across launches. See ``AppEnvironment/claimWindow(id:)``.
    let id: UUID

    /// The repositories this window lists. A view onto the app's pool.
    let repositories: WindowRepositories

    /// The sidebar's models, beside the list itself.
    let repositoryList: RepositoriesModel

    /// The file tree of the worktree this window shows.
    let fileTree: FileTreeModel

    /// The file open in this window's middle pane.
    let editor: EditorModel
    let terminal: TerminalModel

    /// The agent panel, with the sessions it has open for each workspace.
    let agentPanel: AgentPanelModel

    @ObservationIgnored
    private let worktrees: WorkspaceRegistry

    @ObservationIgnored
    private let windows: WindowStore

    /// The workspace this window is showing, or `nil` for none.
    private(set) var activeWorkspaceID: WorkspaceID?

    /// The workspaces this window keeps open, in the order it opened them.
    /// Showing one is a choice among these; the registry keeps all of them
    /// alive for as long as any window names them.
    private(set) var openWorkspaces: [WorkspaceID]

    /// How wide the outer panes were left. Changes live while a pane is being
    /// dragged; ``commitPaneWidths()`` is what writes it down.
    var paneWidths: PaneWidths

    init(
        id: UUID,
        repositories: WindowRepositories,
        repositoryList: RepositoriesModel,
        fileTree: FileTreeModel,
        editor: EditorModel,
        terminal: TerminalModel,
        agentPanel: AgentPanelModel,
        worktrees: WorkspaceRegistry,
        windows: WindowStore,
        restoring snapshot: WindowSnapshot? = nil
    ) {
        self.id = id
        self.repositories = repositories
        self.repositoryList = repositoryList
        self.fileTree = fileTree
        self.editor = editor
        self.terminal = terminal
        self.agentPanel = agentPanel
        self.worktrees = worktrees
        self.windows = windows
        self.activeWorkspaceID = snapshot?.activeWorkspace
        self.openWorkspaces = snapshot?.openWorkspaces ?? []
        self.paneWidths = snapshot?.paneWidths ?? PaneWidths()
        // Not worth a file until something is in it, but once there is one it
        // is kept current even if the window empties again.
        self.hasSnapshot = snapshot != nil
        repositories.onChange = { [weak self] in self?.scheduleSave() }
    }

    /// The workspace this window is showing, resolved from the id. `nil` until
    /// ``showActiveWorkspace()`` has opened it, and again once its folder goes
    /// away.
    var activeWorkspace: Workspace? {
        guard let id = activeWorkspaceID else { return nil }
        return worktrees.workspace(for: id)
    }

    /// Shows `id`, or nothing. Asking for what is already showing changes
    /// nothing, so a repeat click does not restart the work the change drives.
    func activate(_ id: WorkspaceID?) {
        guard id != activeWorkspaceID else { return }
        activeWorkspaceID = id
        if let id, !openWorkspaces.contains(id) { openWorkspaces.append(id) }
        scheduleSave()
    }

    /// Stops keeping a workspace open. If it was the one showing, the window
    /// shows nothing. The workspace itself closes only if no other window is
    /// holding it.
    func forget(_ id: WorkspaceID) async {
        openWorkspaces.removeAll { $0 == id }
        terminal.discard(id)
        agentPanel.discard(id)
        if activeWorkspaceID == id { activeWorkspaceID = nil }
        scheduleSave()
        await worktrees.close(id, holder: self)
    }

    /// Opens the workspaces this window held last time, apart from the one it
    /// is showing, which ``showActiveWorkspace()`` opens.
    ///
    /// Cheap, because none of them drains until a window shows one: a watcher
    /// apiece and no subprocesses.
    func reopenHeldWorkspaces() async {
        for id in openWorkspaces where id != activeWorkspaceID {
            await worktrees.open(id, holder: self)
        }
    }

    /// Opens the workspace ``activeWorkspaceID`` names and points the panes at
    /// it. Run it whenever the id changes; nothing else is torn down.
    func showActiveWorkspace() async {
        // The file from the worktree before is not this one's. Each workspace
        // remembers its own, so this shows that one instead.
        editor.close()
        let id = activeWorkspaceID
        // Opened here, ahead of the tree, so the editor has the workspace to
        // read from. Opening is idempotent: the tree's open finds it.
        let workspace = if let id { await worktrees.open(id, holder: self) } else { nil as Workspace? }
        guard !Task.isCancelled else { return }
        await editor.restore(in: workspace)
        await terminal.show(workspace)
        await agentPanel.show(workspace)
        await fileTree.setRoot(id?.url)
    }

    /// Starts an agent session in a worktree, with `agent` or the one used
    /// last, switching to it first if this
    /// window is showing another.
    ///
    /// The panel is told before the switch, and holds the request until the
    /// switch gets there: the worktree opens asynchronously, and the panel
    /// can only start a session in the workspace it is showing.
    /// Brings an open session forward from the sidebar: its worktree shown,
    /// its tab in front. The panel is told first, for the same reason as below.
    func showAgentSession(_ session: AgentSessionSummary) {
        agentPanel.reveal(session.id, in: session.workspace)
        activate(session.workspace)
    }

    func startAgentSession(in id: WorkspaceID, agent: Agent?) {
        agentPanel.requestSession(in: id, agent: agent)
        activate(id)
    }

    /// Selection only ever opens. A file that goes from disk loses its
    /// selection but not its tab: the editor keeps it, struck through.
    func openSelectedFile() async {
        guard let file = fileTree.selected else { return }
        await editor.open(file)
    }

    /// Keeps the tree's highlight on the tab showing, so clicking a tab,
    /// closing one or cycling moves it too.
    ///
    /// The other direction is ``openSelectedFile()``, so this is a loop — but
    /// a terminating one: selection only ever opens, and opening the file
    /// already showing does nothing, so it stops after one hop. A highlight
    /// pointing at a file you are not looking at is a small lie the pane would
    /// otherwise tell constantly.
    func followShownFile() {
        fileTree.select(editor.file)
    }

    /// Writes down the pane widths. Asked for when a drag ends rather than as it
    /// goes: the disk only needs the width the user let go at.
    func commitPaneWidths() {
        scheduleSave()
    }

    /// Opens the add-repository modal. Here rather than on the sidebar because a
    /// menu command, not just the sidebar's button, asks for it.
    func beginAddingRepository() {
        repositoryList.beginAdding()
    }

    // MARK: - Persisting

    private var hasSnapshot: Bool

    /// The tail of the saves. Each waits for the one before, so an older state
    /// can never be written over a newer one.
    @ObservationIgnored
    private var saving: Task<Void, Never>?

    var snapshot: WindowSnapshot {
        WindowSnapshot(
            id: id,
            openWorkspaces: openWorkspaces,
            activeWorkspace: activeWorkspaceID,
            repositories: repositories.members,
            paneWidths: paneWidths
        )
    }

    /// Writes this window's snapshot, taken when the write runs and not when it
    /// was asked for, so several changes in a row cost the latest state rather
    /// than each in turn.
    ///
    /// A window nothing has happened in writes nothing: it would otherwise be
    /// the most recently used, and the one a relaunch adopts.
    private func scheduleSave() {
        guard hasSnapshot || !snapshot.isBlank else { return }
        hasSnapshot = true
        let previous = saving
        saving = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await windows.save(snapshot)
        }
    }

    /// Waits for every save asked for so far.
    func flushSaves() async {
        await saving?.value
    }

    /// This window is closing for good, as opposed to the app quitting: lets go
    /// of the workspaces only it held and forgets its snapshot.
    func didClose() async {
        terminal.terminateAll()
        agentPanel.terminateAll()
        await flushSaves()
        await worktrees.release(holder: self)
        worktrees.stopDisplaying(from: self)
        await windows.discard(id)
    }
}
