import Core
import Foundation
import Observation
import TerminalUI

/// The agent panel of one window: the sessions it has running for each
/// workspace, and whether the panel is showing.
///
/// A session is opencode's own terminal UI, in a terminal of its own, started
/// in the worktree's root. Nothing here talks to opencode: it is a program in a
/// terminal, as a shell is.
///
/// Per window and per workspace, like the terminal panel's tabs: a terminal
/// view can be in one window at a time, so two windows on one checkout each
/// run their own. Switching workspaces changes which are shown and nothing
/// else; the others keep running.
///
/// What persists is on the workspace (``AgentPanelUIState``) and is only
/// whether the panel was open. The processes are not: a relaunch with the panel
/// open starts one.
@Observable
public final class AgentPanelModel {
    /// What starts a session. `--standalone` so that it is a terminal UI on its
    /// own private server rather than a client of the background service.
    static let command = "exec opencode --standalone"

    private let pty: any PTYClient
    private let environment: [String: String]

    public private(set) var workspace: Workspace?

    private var tabsByWorkspace: [WorkspaceID: [AgentTab]] = [:]
    private var activeByWorkspace: [WorkspaceID: UUID] = [:]
    private var openedByWorkspace: [WorkspaceID: Int] = [:]

    /// A worktree to start a session in once it is the one showing. See
    /// ``requestSession(in:)``.
    private var pending: WorkspaceID?

    /// The panel is showing for the workspace being shown.
    public private(set) var isOpen = false

    /// Changes when the panel should take the keyboard.
    public private(set) var focusRequest = 0

    public init(
        pty: any PTYClient,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.pty = pty
        self.environment = environment
    }

    // MARK: What is showing

    var tabs: [AgentTab] {
        workspace.flatMap { tabsByWorkspace[$0.id] } ?? []
    }

    var activeTab: AgentTab? {
        guard let workspace, let id = activeByWorkspace[workspace.id] else { return tabs.first }
        return tabs.first { $0.id == id } ?? tabs.first
    }

    /// A terminal UI has the keyboard. Read by the commands that mean a tab of
    /// this panel when it does.
    public var hasFocus: Bool { isOpen && activeTab?.screen?.isFocused == true }

    public var canSelectOtherTab: Bool { isOpen && tabs.count > 1 }

    func title(of tab: AgentTab) -> String {
        "Session \(tab.number)"
    }

    // MARK: Showing a workspace

    /// Points the panel at `workspace`: whether it was open, and, if it was, a
    /// session to type in. A session asked for on the way is started instead.
    public func show(_ workspace: Workspace?) async {
        self.workspace = workspace
        guard let workspace else {
            isOpen = false
            return
        }
        isOpen = workspace.uiState(AgentPanelUIState.self).isOpen

        // Asked for before this workspace was showing, and answered now, or not
        // at all: a request for a workspace that never came must not start a
        // session in some other one later.
        let requested = pending
        pending = nil
        if requested == workspace.id {
            await startSession()
        } else if isOpen, tabs.isEmpty {
            await startSession()
        }
    }

    // MARK: The panel

    public func toggle() async {
        guard workspace != nil else { return }
        if isOpen {
            setOpen(false)
        } else {
            setOpen(true)
            if tabs.isEmpty { await startSession() }
            focusRequest += 1
        }
    }

    public func hide() {
        setOpen(false)
    }

    private func setOpen(_ open: Bool) {
        guard let workspace else { return }
        isOpen = open
        let state = workspace.uiState(AgentPanelUIState.self)
        guard state.isOpen != open else { return }
        state.isOpen = open
        workspace.scheduleSnapshotSave()
    }

    // MARK: Sessions

    /// Asks for a new session in `id`. If that is the workspace showing, it
    /// starts now; otherwise when the window gets there, which it is already
    /// on its way to. See ``show(_:)``.
    public func requestSession(in id: WorkspaceID) {
        if workspace?.id == id {
            Task { await startSession() }
        } else {
            pending = id
        }
    }

    /// Starts opencode in the root of the workspace showing, whichever tab is
    /// in front: a new session is a fresh start, not a copy of the one beside
    /// it.
    public func startSession() async {
        guard let workspace else { return }
        let id = workspace.id
        let number = (openedByWorkspace[id] ?? 0) + 1
        openedByWorkspace[id] = number

        let tab = AgentTab(number: number)
        watch(tab, in: id)
        tabsByWorkspace[id, default: []].append(tab)
        activeByWorkspace[id] = tab.id
        setOpen(true)
        focusRequest += 1
        await attach(tab, in: workspace)
        // Told again once there is a screen for the keyboard to go to.
        if self.workspace?.id == id { focusRequest += 1 }
    }

    func select(_ tab: AgentTab) {
        guard let workspace, tabs.contains(where: { $0.id == tab.id }) else { return }
        activeByWorkspace[workspace.id] = tab.id
        focusRequest += 1
    }

    public func selectNextTab() { cycle(by: 1) }
    public func selectPreviousTab() { cycle(by: -1) }

    private func cycle(by step: Int) {
        let tabs = tabs
        guard tabs.count > 1, let active = activeTab, let index = tabs.firstIndex(where: { $0.id == active.id }) else {
            return
        }
        select(tabs[(index + step + tabs.count) % tabs.count])
    }

    public func closeActiveTab() {
        if let tab = activeTab { close(tab) }
    }

    /// Ends a session's terminal UI and takes its tab away. The panel stays,
    /// so the next session is one click away.
    func close(_ tab: AgentTab) {
        guard let id = tabsByWorkspace.first(where: { $0.value.contains { $0.id == tab.id } })?.key else { return }
        tab.terminate()
        remove(tab, from: id)
    }

    private func remove(_ tab: AgentTab, from id: WorkspaceID) {
        guard var tabs = tabsByWorkspace[id], let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        tabsByWorkspace[id] = tabs.isEmpty ? nil : tabs
        if activeByWorkspace[id] == tab.id {
            activeByWorkspace[id] = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
        if workspace?.id == id { focusRequest += 1 }
    }

    /// Starts opencode again in a tab that stopped.
    func reattach(_ tab: AgentTab) async {
        guard let workspace else { return }
        await attach(tab, in: workspace)
        focusRequest += 1
    }

    // MARK: Terminal UIs

    /// opencode through the user's own shell, so that it is found where their
    /// terminal would find it.
    private func attach(_ tab: AgentTab, in workspace: Workspace) async {
        let spec = ShellLaunch.command(
            Self.command,
            environment: environment,
            directory: workspace.id.url,
            size: PTYSize(columns: 100, rows: 30)
        )
        await tab.attach(using: pty, spec: spec)
    }

    /// The terminal UI stopped by itself. Quitting it ends the tab, as quitting
    /// a shell does; anything else stays up with what it said, and a way to
    /// start it again.
    private func watch(_ tab: AgentTab, in id: WorkspaceID) {
        tab.onExit = { [weak self] tab, code in
            guard let self else { return }
            if code == 0 {
                remove(tab, from: id)
            } else {
                tab.screen?.announce("[Process exited with code \(code)]")
            }
        }
    }

    // MARK: Letting go

    /// Ends every session for a workspace this window has stopped keeping.
    public func discard(_ id: WorkspaceID) {
        for tab in tabsByWorkspace[id] ?? [] { tab.terminate() }
        tabsByWorkspace[id] = nil
        activeByWorkspace[id] = nil
        openedByWorkspace[id] = nil
        if workspace?.id == id { isOpen = false }
    }

    /// Ends every session: the window is closing.
    public func terminateAll() {
        for tabs in tabsByWorkspace.values {
            for tab in tabs { tab.terminate() }
        }
        tabsByWorkspace = [:]
        activeByWorkspace = [:]
    }
}
