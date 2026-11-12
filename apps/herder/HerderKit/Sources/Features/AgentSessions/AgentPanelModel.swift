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
    private let commands: any CommandClient
    private let clock: any ClockClient
    private let environment: [String: String]

    /// How often each session is looked at. Output within one of these is
    /// work; a whole one without any is quiet.
    private let sampleInterval: Duration

    /// What this window has open, for its sidebar to list. Written here, read
    /// there. Its ``WindowAgentSessions/store`` is where each session is
    /// written down as it starts and ends.
    public let sessions: WindowAgentSessions

    /// The key a worktree's history is kept under: its repository's folder.
    /// Set by whoever knows the window's repositories; a worktree none of
    /// them owns is kept under its own folder.
    @ObservationIgnored public var historyKey: (WorkspaceID) async -> PathKey? = { _ in nil }

    /// Asked for when a file named in a session's output is clicked: the
    /// file, and the line and column the text gave. A feature cannot reach the
    /// editor, so whoever composes the window decides where it opens.
    @ObservationIgnored public var onOpenFile: ((URL, Int?, Int?) -> Void)?

    @ObservationIgnored private var sampling: Task<Void, Never>?

    /// Tabs whose session is being looked up, so one lookup runs at a time.
    @ObservationIgnored private var lookingUp: Set<UUID> = []

    /// A session to bring forward once its workspace is showing. See
    /// ``reveal(_:in:)``.
    private var pendingFocus = false

    /// The agents a session can be started with.
    public let catalog: AgentCatalog

    /// A session from the history to pick up once its worktree is the one
    /// showing. See ``requestResume(_:)``.
    private var pendingResume: AgentSession?

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
        commands: any CommandClient,
        clock: any ClockClient,
        catalog: AgentCatalog,
        sessions: WindowAgentSessions,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sampleInterval: Duration = .seconds(1)
    ) {
        self.pty = pty
        self.commands = commands
        self.clock = clock
        self.sampleInterval = sampleInterval
        self.catalog = catalog
        self.sessions = sessions
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

    /// The name the person gave it, or else the agent's name, and which of its
    /// sessions this is once there is more than one.
    func title(of tab: AgentTab) -> String {
        if let name = tab.customName { return name }
        return tab.number > 1 ? "\(tab.agent.displayName) \(tab.number)" : tab.agent.displayName
    }

    /// What the header and the sidebar call a session: the person's name, else
    /// the title the program reports, else the one on record, else
    /// ``title(of:)``.
    func subject(of tab: AgentTab) -> String {
        tab.customName ?? tab.programTitle ?? sessions.store.session(tab.id)?.title ?? title(of: tab)
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
        let resuming = pendingResume
        pendingResume = nil
        if let requested, requested.workspace == workspace.id {
            await startSession(requested.agent)
        } else if let resuming, resuming.worktree == workspace.id {
            await resume(resuming)
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
        // Even with no tabs: that is what ends a session whose tab was lost.
        let claimed = Set(state.tabs.map(\.id))
        Task { [store = sessions.store, historyKey] in
            await store.reconcile(id, in: await historyKey(id) ?? id.root, claimed: claimed)
        }
        guard !state.tabs.isEmpty else { return }
        let tabs = state.tabs.map {
            AgentTab(
                id: $0.id, agent: $0.agent, number: $0.number, name: $0.name,
                restored: true, sessionID: $0.session, startedAt: $0.started
            )
        }
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

        let tab = AgentTab(agent: agent, number: nextNumber(of: agent, in: workspace.id))
        await open(tab, in: workspace)
    }

    /// Brings a session from the history back in a new tab of its own, in the
    /// workspace showing, which must be the worktree it ran in, or in front
    /// if it has one already. It is the same session again, but only to be
    /// read: the record stays ended until the person says something in the
    /// tab (see ``watch(_:in:)``).
    ///
    /// Refused for one that cannot be picked up: its agent is gone, or gave
    /// no id to resume it by. The sidebar says so; the last session in the
    /// worktree is not a stand-in, because it may be another.
    public func resume(_ session: AgentSession) async {
        guard let workspace, workspace.id == session.worktree else { return }
        if tabsByWorkspace[workspace.id]?.contains(where: { $0.id == session.id }) == true {
            reveal(session.id, in: workspace.id)
            return
        }
        guard let agent = catalog.agent(session.agentID), agent.isRunnable,
              let sessionID = session.sessionID
        else { return }
        catalog.markUsed(agent)
        let tab = AgentTab(
            id: session.id, agent: agent, number: nextNumber(of: agent, in: workspace.id), name: session.name,
            restored: true,
            // An agent that names its own sessions is told which; for one
            // that is given an id, the tab's own is the session's.
            sessionID: agent.looksUpSessions ? sessionID : nil,
            startedAt: session.startedAt
        )
        await open(tab, in: workspace)
    }

    /// Asks for a session from the history to be picked up in its worktree.
    /// If that is the workspace showing it happens now; otherwise when the
    /// window gets there. See ``show(_:)``.
    public func requestResume(_ session: AgentSession) {
        if workspace?.id == session.worktree {
            Task { await resume(session) }
        } else {
            pendingResume = session
        }
    }

    private func nextNumber(of agent: Agent, in id: WorkspaceID) -> Int {
        let number = (openedByWorkspace[id]?[agent.id] ?? 0) + 1
        openedByWorkspace[id, default: [:]][agent.id] = number
        return number
    }

    /// Puts `tab` in front in `workspace` and starts it.
    private func open(_ tab: AgentTab, in workspace: Workspace) async {
        let id = workspace.id
        watch(tab, in: id)
        tabsByWorkspace[id, default: []].append(tab)
        activeByWorkspace[id] = tab.id
        focusRequest += 1
        startSampling()
        remember(id)
        publish()
        await attach(tab, in: workspace)
        // Again, now that it has a start time to remember.
        remember(id)
        publish()
        // Told again once there is a screen for the keyboard to go to.
        if self.workspace?.id == id { focusRequest += 1 }
    }

    // MARK: History

    /// Writes down a session whose agent is running and has been said
    /// something to: a new one, or one restored from before that has none
    /// yet. One already written down is left as it is. Called when either
    /// becomes true, whichever is second.
    private func recordStart(of tab: AgentTab, in workspace: Workspace) {
        guard tab.phase == .running, tab.hasConversed, let started = tab.startedAt else { return }
        let branch: String? = switch workspace.checkout {
        case .branch(let name): name
        case .detached(let sha): String(sha.prefix(7))
        case nil: nil
        }
        let session = AgentSession(
            id: tab.id,
            agentID: tab.agent.id,
            agentName: tab.agent.displayName,
            sessionID: mintsSessionID(of: tab.agent) ? tab.sessionName : tab.sessionID,
            worktree: workspace.id,
            branch: branch,
            title: subject(of: tab),
            name: tab.customName,
            startedAt: started
        )
        Task { [store = sessions.store, historyKey] in
            await store.begin(session, in: await historyKey(session.worktree) ?? session.worktree.root)
        }
    }

    /// Whether Herder gives the agent the session's id, so it is known from
    /// the start. An agent that names its own is looked up instead, and one
    /// whose commands take no id has none to know.
    private func mintsSessionID(of agent: Agent) -> Bool {
        !agent.looksUpSessions
            && [agent.command, agent.resumeCommand].contains { $0?.contains(Agent.sessionToken) == true }
    }

    func select(_ tab: AgentTab) {
        guard let workspace, tabs.contains(where: { $0.id == tab.id }) else { return }
        activeByWorkspace[workspace.id] = tab.id
        focusRequest += 1
        remember(workspace.id)
        publish()
        if tab.phase == .waiting { Task { await resumeActive() } }
    }

    /// Names a tab, or with a blank name gives it back the agent's. Hands the
    /// keyboard back to the terminal UI: the name was typed over it.
    func rename(_ tab: AgentTab, to name: String) {
        guard setName(of: tab, to: name) else { return }
        select(tab)
    }

    /// Names the tab of session `id`, from outside the panel: the sidebar.
    /// Leaves which tab is in front, and the keyboard, where they are.
    public func rename(_ id: UUID, to name: String) {
        guard let tab = tabsByWorkspace.values.joined().first(where: { $0.id == id }) else { return }
        setName(of: tab, to: name)
    }

    @discardableResult
    private func setName(of tab: AgentTab, to name: String) -> Bool {
        guard let id = workspace(holding: tab) else { return false }
        tab.rename(to: name)
        remember(id)
        publish()
        return true
    }

    private func workspace(holding tab: AgentTab) -> WorkspaceID? {
        tabsByWorkspace.first { $0.value.contains { $0.id == tab.id } }?.key
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
        guard let id = workspace(holding: tab) else { return }
        tab.terminate()
        sessions.store.end(tab.id, because: .closed)
        remove(tab, from: id)
    }

    /// Closes the tab of session `id`, from outside the panel: the sidebar.
    public func close(_ id: UUID) {
        guard let tab = tabsByWorkspace.values.joined().first(where: { $0.id == id }) else { return }
        close(tab)
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
        if tab.hasStarted, tab.isMissingSessionID { await lookUpSession(of: tab, in: workspace.id) }
        // An agent that names its own sessions cannot be pointed at one
        // nobody found, so that one starts afresh.
        let resuming = tab.hasStarted && !tab.isMissingSessionID
        let line = tab.agent.commandLine(session: tab.sessionName, resuming: resuming)
        var spec = ShellLaunch.command(
            "exec \(line)",
            environment: environment(for: tab.agent),
            directory: workspace.id.url,
            size: PTYSize(columns: 100, rows: 30)
        )
        spec.pidVariable = AgentMark.variable
        await tab.attach(using: pty, spec: spec)
        recordStart(of: tab, in: workspace)
    }

    /// The app's environment with the agent's over it. A preset's comes from
    /// the preset as it is now, not the tab's copy: it is Herder's choice, not
    /// the person's, so a tab saved before it changed takes the change too.
    private func environment(for agent: Agent) -> [String: String] {
        let preset = Agent.presets.first { $0.id == agent.id }
        return environment.merging((preset ?? agent).environment ?? [:]) { $1 }
    }

    /// The person said something to the terminal UI, which is when its
    /// session goes into the history, or comes back out of it if it was
    /// ended and opened to be read. Or it stopped by itself: quitting it
    /// ends the tab, as quitting a shell does; anything else stays up with
    /// what it said, and a way to start it again.
    private func watch(_ tab: AgentTab, in id: WorkspaceID) {
        tab.onOpenFile = { [weak self] url, line, column in self?.onOpenFile?(url, line, column) }
        tab.onConverse = { [weak self] tab in
            guard let self, let workspace = workspaceObjects[id]?.workspace else { return }
            recordStart(of: tab, in: workspace)
            // A session opened only to be read is closed until now.
            sessions.store.reopen(tab.id)
            publish()
        }
        tab.onExit = { [weak self] tab, code in
            guard let self else { return }
            if code == 0 {
                sessions.store.end(tab.id, because: .exited)
                remove(tab, from: id)
            } else {
                tab.screen?.announce("[Process exited with code \(code)]")
                publish()
            }
        }
    }

    // MARK: Looking up sessions

    /// Asks an agent that names its own sessions which one this tab started,
    /// and keeps the answer. Run when a turn has ended, by which time the
    /// session exists, and again before resuming if that found nothing.
    private func lookUpSession(of tab: AgentTab, in id: WorkspaceID) async {
        guard let lookup = tab.agent.sessionLookup, tab.isMissingSessionID, let started = tab.startedAt,
              !lookingUp.contains(tab.id)
        else { return }
        lookingUp.insert(tab.id)
        defer { lookingUp.remove(tab.id) }

        guard let output = await commands.output(of: lookup, in: id.url) else { return }
        let claimed = Set(tabsByWorkspace.values.joined().compactMap(\.sessionID))
        guard
            tab.isMissingSessionID,
            let session = AgentSessionLookup.match(
                AgentSessionLookup.candidates(in: output),
                directory: id.root,
                started: started,
                claimed: claimed
            ),
            // It goes into a command line.
            AgentSessionLookup.isSafe(session)
        else { return }
        tab.setSessionID(session)
        remember(id)
    }

    // MARK: Remembering

    /// Writes down the sessions open in `id`, and which is in front, on that
    /// workspace. Only for a change the person made: closing the window ends
    /// the processes but remembers the tabs, so they come back with it.
    private func remember(_ id: WorkspaceID) {
        guard let workspace = workspaceObjects[id]?.workspace else { return }
        let state = workspace.uiState(AgentPanelUIState.self)
        let tabs = (tabsByWorkspace[id] ?? []).map {
            AgentPanelUIState.Tab(
                id: $0.id, agent: $0.agent, number: $0.number, name: $0.customName,
                session: $0.sessionID, started: $0.startedAt
            )
        }
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

    /// Ends every session and keeps the tabs, which come back on the next
    /// launch: the app is quitting.
    public func terminateForQuit() {
        for tab in tabsByWorkspace.values.joined() { tab.terminateNow() }
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
                for (id, tabs) in tabsByWorkspace {
                    for tab in tabs where tab.sample(now: now) && tab.isMissingSessionID {
                        Task { await lookUpSession(of: tab, in: id) }
                    }
                }
                publish()
            }
        }
    }

    /// Tells ``sessions`` what this window has open, every workspace's, in
    /// the order each was opened, and which is in front. Also how a session
    /// that is written down learns its title and its agent's id: see
    /// ``AgentSessions/note(_:window:at:)``.
    private func publish() {
        let reports = tabsByWorkspace
            .sorted { $0.key.root < $1.key.root }
            .flatMap { workspace, tabs in
                tabs.map { tab in
                    AgentSessions.Report(
                        id: tab.id,
                        worktree: workspace,
                        agentID: tab.agent.id,
                        agentName: tab.agent.displayName,
                        // The person's name over the program's. Neither, for a
                        // paused tab, which keeps the title it had.
                        title: tab.customName ?? tab.programTitle,
                        name: tab.customName,
                        fallbackTitle: title(of: tab),
                        sessionID: tab.sessionID,
                        state: tab.state,
                        lastActivity: tab.lastActivity,
                        startedAt: tab.startedAt
                    )
                }
            }
        sessions.publish(reports, focused: activeTab?.id)
    }
}
