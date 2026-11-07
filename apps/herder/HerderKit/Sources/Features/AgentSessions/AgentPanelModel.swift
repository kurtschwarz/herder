import Core
import Foundation
import Observation
import TerminalUI

/// The agent panel of one window: the sessions it has running for each
/// workspace. The panel is always on screen; only what is in it changes.
///
/// A session is an agent's own terminal UI — Claude Code, Codex, opencode, Pi,
/// or one the user added — in a terminal of its own, started in the
/// worktree's root. Nothing here talks to any of them: each is a program in a
/// terminal, as a shell is.
///
/// Per window and per workspace, like the terminal panel's tabs: a terminal
/// view can be in one window at a time, so two windows on one checkout each
/// run their own. Switching workspaces changes which are shown and nothing
/// else; the others keep running.
///
/// Nothing persists. A process cannot be brought back, and starting one for
/// every worktree shown would cost a process each: a worktree with no sessions
/// shows a button per agent instead.
@Observable
public final class AgentPanelModel {
    private let pty: any PTYClient
    private let environment: [String: String]

    /// The agents a session can be started with.
    public let catalog: AgentCatalog

    public private(set) var workspace: Workspace?

    private var tabsByWorkspace: [WorkspaceID: [AgentTab]] = [:]
    private var activeByWorkspace: [WorkspaceID: UUID] = [:]
    private var openedByWorkspace: [WorkspaceID: [Agent.ID: Int]] = [:]

    /// A session to start once its worktree is the one showing, with the
    /// agent asked for, or `nil` for the one used last. See
    /// ``requestSession(in:agent:)``.
    private var pending: (workspace: WorkspaceID, agent: Agent?)?

    /// Changes when the panel should take the keyboard.
    public private(set) var focusRequest = 0

    public init(
        pty: any PTYClient,
        catalog: AgentCatalog,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.pty = pty
        self.catalog = catalog
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
    public var hasFocus: Bool { activeTab?.screen?.isFocused == true }

    public var canSelectOtherTab: Bool { tabs.count > 1 }

    /// The agent's name, and which of its sessions this is once there is more
    /// than one.
    func title(of tab: AgentTab) -> String {
        tab.number > 1 ? "\(tab.agent.displayName) \(tab.number)" : tab.agent.displayName
    }

    // MARK: Showing a workspace

    /// Points the panel at `workspace`'s sessions, and starts the one asked
    /// for on the way there, if any.
    public func show(_ workspace: Workspace?) async {
        self.workspace = workspace
        guard let workspace else { return }

        // Asked for before this workspace was showing, and answered now, or not
        // at all: a request for a workspace that never came must not start a
        // session in some other one later.
        let requested = pending
        pending = nil
        if let requested, requested.workspace == workspace.id {
            await startSession(requested.agent)
        }
    }

    // MARK: Sessions

    /// Asks for a new session in `id`, with `agent` or the one used last. If
    /// that is the workspace showing, it starts now; otherwise when the window
    /// gets there, which it is already on its way to. See ``show(_:)``.
    public func requestSession(in id: WorkspaceID, agent: Agent? = nil) {
        if workspace?.id == id {
            Task { await startSession(agent) }
        } else {
            pending = (id, agent)
        }
    }

    /// Starts `agent`, or the one used last, in the root of the workspace
    /// showing, whichever tab is in front: a new session is a fresh start, not
    /// a copy of the one beside it.
    public func startSession(_ agent: Agent? = nil) async {
        guard let workspace else { return }
        let agent = agent ?? catalog.lastUsed
        guard agent.isRunnable else { return }
        catalog.markUsed(agent)

        let id = workspace.id
        let number = (openedByWorkspace[id]?[agent.id] ?? 0) + 1
        openedByWorkspace[id, default: [:]][agent.id] = number

        let tab = AgentTab(agent: agent, number: number)
        watch(tab, in: id)
        tabsByWorkspace[id, default: []].append(tab)
        activeByWorkspace[id] = tab.id
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

    /// Ends a session's terminal UI and takes its tab away.
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

    /// Starts the agent again in a tab that stopped.
    func reattach(_ tab: AgentTab) async {
        guard let workspace else { return }
        await attach(tab, in: workspace)
        focusRequest += 1
    }

    // MARK: Terminal UIs

    /// The agent's command through the user's own shell, so that it is found
    /// where their terminal would find it. The command is the user's own, typed
    /// in Settings or one of the presets, and is run as they wrote it.
    private func attach(_ tab: AgentTab, in workspace: Workspace) async {
        let spec = ShellLaunch.command(
            "exec \(tab.agent.command)",
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
