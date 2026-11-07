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
/// The open sessions persist, on the workspace (``AgentPanelUIState``). A
/// process cannot be brought back, so a remembered tab comes back paused and
/// is resumed, with the agent's resume command, when it is shown: the one in
/// front at once, the others when they are clicked. A worktree with no
/// sessions starts nothing by itself, and shows a button per agent instead.
@Observable
public final class AgentPanelModel {
    private let pty: any PTYClient
    private let clock: any ClockClient
    private let environment: [String: String]

    /// How often each session is looked at. Output within one of these is
    /// work; a whole one without any is quiet.
    private let sampleInterval: Duration

    /// What this window's sidebar lists. Written here, read there.
    public let openSessions: OpenAgentSessions

    @ObservationIgnored private var sampling: Task<Void, Never>?

    /// A session to bring forward once its workspace is showing. See
    /// ``reveal(_:in:)``.
    private var pendingFocus = false

    /// The agents a session can be started with.
    public let catalog: AgentCatalog

    public private(set) var workspace: Workspace?

    private var tabsByWorkspace: [WorkspaceID: [AgentTab]] = [:]
    private var activeByWorkspace: [WorkspaceID: UUID] = [:]
    private var openedByWorkspace: [WorkspaceID: [Agent.ID: Int]] = [:]

    /// The workspaces whose sessions are here, to remember them on. Weak: the
    /// registry owns a workspace, and a closed one should not live on here.
    @ObservationIgnored private var workspaceObjects: [WorkspaceID: WeakWorkspace] = [:]

    private struct WeakWorkspace {
        weak var workspace: Workspace?
    }

    /// A session to start once its worktree is the one showing, with the
    /// agent asked for, or `nil` for the one used last. See
    /// ``requestSession(in:agent:)``.
    private var pending: (workspace: WorkspaceID, agent: Agent?)?

    /// Changes when the panel should take the keyboard.
    public private(set) var focusRequest = 0

    public init(
        pty: any PTYClient,
        clock: any ClockClient,
        catalog: AgentCatalog,
        openSessions: OpenAgentSessions,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sampleInterval: Duration = .seconds(1)
    ) {
        self.pty = pty
        self.clock = clock
        self.sampleInterval = sampleInterval
        self.catalog = catalog
        self.openSessions = openSessions
        self.environment = environment
    }

    deinit {
        sampling?.cancel()
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

    /// Points the panel at `workspace`'s sessions, remembered ones included,
    /// resumes the one in front, and starts the one asked for on the way there,
    /// if any.
    public func show(_ workspace: Workspace?) async {
        self.workspace = workspace
        defer { publish() }
        guard let workspace else { return }
        restore(workspace)
        if pendingFocus {
            pendingFocus = false
            focusRequest += 1
        }

        // Asked for before this workspace was showing, and answered now, or not
        // at all: a request for a workspace that never came must not start a
        // session in some other one later.
        let requested = pending
        pending = nil
        if let requested, requested.workspace == workspace.id {
            await startSession(requested.agent)
        } else {
            await resumeActive()
        }
    }

    /// Brings back the sessions `workspace` had open, paused, unless this
    /// window has them already. Called for every workspace the window holds,
    /// so the sidebar lists them before they are shown.
    public func restore(_ workspace: Workspace) {
        let id = workspace.id
        workspaceObjects[id] = WeakWorkspace(workspace: workspace)
        guard tabsByWorkspace[id] == nil else { return }
        let state = workspace.uiState(AgentPanelUIState.self)
        guard !state.tabs.isEmpty else { return }
        let tabs = state.tabs.map { AgentTab(id: $0.id, agent: $0.agent, number: $0.number, restored: true) }
        for tab in tabs {
            watch(tab, in: id)
            openedByWorkspace[id, default: [:]][tab.agent.id] = max(
                openedByWorkspace[id]?[tab.agent.id] ?? 0, tab.number
            )
        }
        tabsByWorkspace[id] = tabs
        activeByWorkspace[id] = state.active
        startSampling()
        publish()
    }

    /// Resumes the tab in front if it is one still waiting from before.
    private func resumeActive() async {
        guard let workspace, let tab = activeTab, tab.phase == .waiting else { return }
        await attach(tab, in: workspace)
        publish()
    }

    // MARK: Sessions

    /// Brings a session forward in `workspace`, which the window is showing or
    /// on its way to: the tab goes in front now, and takes the keyboard once
    /// it is on screen.
    public func reveal(_ id: UUID, in workspace: WorkspaceID) {
        guard tabsByWorkspace[workspace]?.contains(where: { $0.id == id }) == true else { return }
        activeByWorkspace[workspace] = id
        if self.workspace?.id == workspace {
            focusRequest += 1
            Task { await resumeActive() }
        } else {
            pendingFocus = true
        }
        publish()
    }

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
        startSampling()
        remember(id)
        publish()
        await attach(tab, in: workspace)
        publish()
        // Told again once there is a screen for the keyboard to go to.
        if self.workspace?.id == id { focusRequest += 1 }
    }

    func select(_ tab: AgentTab) {
        guard let workspace, tabs.contains(where: { $0.id == tab.id }) else { return }
        activeByWorkspace[workspace.id] = tab.id
        focusRequest += 1
        remember(workspace.id)
        publish()
        if tab.phase == .waiting { Task { await resumeActive() } }
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
        remember(id)
        publish()
        if workspace?.id == id { Task { await resumeActive() } }
    }

    /// Starts the agent again in a tab that stopped.
    func reattach(_ tab: AgentTab) async {
        guard let workspace else { return }
        await attach(tab, in: workspace)
        focusRequest += 1
        publish()
    }

    // MARK: Terminal UIs

    /// The agent's command through the user's own shell, so that it is found
    /// where their terminal would find it. The command is the user's own, typed
    /// in Settings or one of the presets, and is run as they wrote it.
    private func attach(_ tab: AgentTab, in workspace: Workspace) async {
        let line = tab.agent.commandLine(for: tab.id, resuming: tab.hasStarted)
        let spec = ShellLaunch.command(
            "exec \(line)",
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
                publish()
            }
        }
    }

    // MARK: Remembering

    /// Writes down the sessions open in `id`, and which is in front, on that
    /// workspace. Only for a change the person made: closing the window ends
    /// the processes but remembers the tabs, so they come back with it.
    private func remember(_ id: WorkspaceID) {
        guard let workspace = workspaceObjects[id]?.workspace else { return }
        let state = workspace.uiState(AgentPanelUIState.self)
        let tabs = (tabsByWorkspace[id] ?? []).map { AgentPanelUIState.Tab(id: $0.id, agent: $0.agent, number: $0.number) }
        let active = activeByWorkspace[id]
        guard state.tabs != tabs || state.active != active else { return }
        state.tabs = tabs
        state.active = active
        workspace.scheduleSnapshotSave()
    }

    // MARK: Letting go

    /// Ends every session for a workspace this window has stopped keeping.
    public func discard(_ id: WorkspaceID) {
        for tab in tabsByWorkspace[id] ?? [] { tab.terminate() }
        tabsByWorkspace[id] = nil
        activeByWorkspace[id] = nil
        openedByWorkspace[id] = nil
        workspaceObjects[id] = nil
        publish()
    }

    /// Ends every session: the window is closing.
    public func terminateAll() {
        for tabs in tabsByWorkspace.values {
            for tab in tabs { tab.terminate() }
        }
        tabsByWorkspace = [:]
        activeByWorkspace = [:]
        sampling?.cancel()
        sampling = nil
        publish()
    }

    // MARK: Telling the sidebar

    /// Looks at every session once a ``sampleInterval`` for as long as any is
    /// open, which
    /// is how a quiet one turns idle without anything happening to say so.
    private func startSampling() {
        guard sampling == nil else { return }
        sampling = Task { [weak self, clock, sampleInterval] in
            while !Task.isCancelled {
                do { try await clock.sleep(for: sampleInterval) } catch { return }
                guard let self else { return }
                let now = Date()
                for tab in tabsByWorkspace.values.joined() { tab.sample(now: now) }
                publish()
            }
        }
    }

    /// Writes what is open into ``openSessions``, every workspace's, in the
    /// order each was opened.
    private func publish() {
        let summaries = tabsByWorkspace
            .sorted { $0.key.root < $1.key.root }
            .flatMap { workspace, tabs in
                tabs.map { tab in
                    AgentSessionSummary(
                        id: tab.id,
                        workspace: workspace,
                        title: tab.programTitle ?? title(of: tab),
                        agentName: tab.agent.displayName,
                        state: tab.state,
                        lastActivity: tab.lastActivity
                    )
                }
            }
        openSessions.update(summaries, focused: activeTab?.id)
    }
}
