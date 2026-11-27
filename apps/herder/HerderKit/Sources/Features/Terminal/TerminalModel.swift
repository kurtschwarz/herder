import Core
import DesignSystem
import Foundation
import Observation
import TerminalUI

/// The terminal panel of one window: the shells it has open for each
/// workspace, and whether the panel is showing.
///
/// Per window and per workspace, like the editor's documents: a terminal view
/// can be in one window at a time, so two windows on one checkout each have
/// their own shells. Switching workspaces changes which are shown and nothing
/// else; the others keep running.
///
/// What persists is on the workspace (``TerminalUIState``) and is only whether
/// the panel was open and how tall. The shells are not: a relaunch with the
/// panel open starts one.
@Observable
public final class TerminalModel {
    private let pty: any PTYClient
    private let clock: any ClockClient
    private let environment: [String: String]
    private let home: URL

    /// Every tab with a process running, in every window, for the Task
    /// Manager to find. This panel's shells are entered as they start.
    private let processes: RunningProcesses
    private let window: UUID

    public private(set) var workspace: Workspace?

    /// A tab to bring forward once its workspace is showing. See
    /// ``reveal(_:in:)``.
    private var pendingReveal: WorkspaceID?

    /// Asked for when the Task Manager shows a shell: its tab in front, in
    /// its workspace, and its window raised. A feature cannot reach the window,
    /// so whoever composes it decides how.
    @ObservationIgnored public var onShowTab: ((UUID, WorkspaceID) -> Void)?

    private var tabsByWorkspace: [WorkspaceID: [TerminalTab]] = [:]
    private var activeByWorkspace: [WorkspaceID: UUID] = [:]

    /// The panel is showing for the workspace being shown.
    public private(set) var isOpen = false

    /// What the user dragged the panel to, if they have.
    private(set) var storedHeight: CGFloat?

    /// Changes when the panel should take the keyboard.
    public private(set) var focusRequest = 0

    /// A tab with something running in it, waiting for the person to say
    /// whether to end it.
    struct ClosePrompt: Equatable {
        let tabID: UUID
        let command: String
    }

    private(set) var closePrompt: ClosePrompt?

    /// Why the last shell would not start, until it is dismissed.
    public private(set) var spawnFailure: String?

    /// Asked for when a file named in a shell's output is clicked: the file,
    /// and the line and column the text gave. Whoever composes the window
    /// decides where it opens, as a feature cannot reach the editor.
    @ObservationIgnored public var onOpenFile: ((URL, Int?, Int?) -> Void)?

    static let limits = PanelHeight.Limits(
        defaultHeight: Theme.Size.defaultTerminalHeight,
        minimumPanel: Theme.Size.minTerminalHeight,
        minimumEditor: Theme.Size.minEditorHeight
    )

    /// Lines of history a new tab keeps. Set from the settings; a tab already
    /// open keeps what it was made with.
    public var scrollbackLines = TerminalScreen.scrollbackLines

    public init(
        pty: any PTYClient,
        clock: any ClockClient,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        processes: RunningProcesses = RunningProcesses(),
        window: UUID = UUID()
    ) {
        self.processes = processes
        self.window = window
        self.pty = pty
        self.clock = clock
        self.environment = environment
        self.home = home
    }

    // MARK: What is showing

    var tabs: [TerminalTab] {
        workspace.flatMap { tabsByWorkspace[$0.id] } ?? []
    }

    var activeTab: TerminalTab? {
        guard let workspace, let id = activeByWorkspace[workspace.id] else { return tabs.first }
        return tabs.first { $0.id == id } ?? tabs.first
    }

    /// A terminal has the keyboard. Read by the commands that mean a terminal
    /// tab when it does and an editor tab when it does not.
    public var hasFocus: Bool { isOpen && activeTab?.screen.isFocused == true }

    public var hasTabs: Bool { !tabs.isEmpty }
    public var canSelectOtherTab: Bool { isOpen && tabs.count > 1 }

    /// How the home folder is written in the header.
    func label(for directory: URL) -> String {
        HomeRelativePath.label(for: directory, home: home)
    }

    // MARK: Showing a workspace

    /// Points the panel at `workspace`: its remembered state, and, if the
    /// panel was open, a shell to type in.
    public func show(_ workspace: Workspace?) async {
        self.workspace = workspace
        guard let workspace else {
            isOpen = false
            return
        }
        let state = workspace.uiState(TerminalUIState.self)
        isOpen = state.isOpen
        storedHeight = state.height
        if pendingReveal == workspace.id {
            setOpen(true)
            focusRequest += 1
        }
        pendingReveal = nil
        if isOpen, tabs.isEmpty { await openTab() }
    }

    // MARK: The panel

    public func toggle() async {
        guard workspace != nil else { return }
        if isOpen {
            setOpen(false)
        } else {
            setOpen(true)
            if tabs.isEmpty { await openTab() }
            focusRequest += 1
        }
    }

    public func hide() {
        setOpen(false)
    }

    private func setOpen(_ open: Bool) {
        guard let workspace else { return }
        isOpen = open
        let state = workspace.uiState(TerminalUIState.self)
        guard state.isOpen != open else { return }
        state.isOpen = open
        workspace.scheduleSnapshotSave()
    }

    public func height(in available: CGFloat) -> CGFloat {
        PanelHeight.resolved(storedHeight, in: available, limits: Self.limits)
    }

    /// Follows a drag. Held to the limits as it goes, and not written to disk
    /// until ``commitHeight()``.
    public func resize(to proposed: CGFloat, in available: CGFloat) {
        storedHeight = PanelHeight.clamp(proposed, in: available, limits: Self.limits)
    }

    public func resetHeight() {
        storedHeight = nil
        commitHeight()
    }

    public func commitHeight() {
        guard let workspace else { return }
        let state = workspace.uiState(TerminalUIState.self)
        guard state.height != storedHeight else { return }
        state.height = storedHeight
        workspace.scheduleSnapshotSave()
    }

    // MARK: Tabs

    /// Starts a shell in the worktree's root, whichever tab is showing: a new
    /// tab is a fresh start, not a copy of the one beside it.
    public func openTab() async {
        guard let workspace else { return }
        let id = workspace.id
        let spec = ShellLaunch.spec(
            environment: environment, directory: id.url, size: PTYSize(columns: 80, rows: 24)
        )
        do {
            let session = try await pty.spawn(spec)
            let tab = TerminalTab(session: session, size: spec.size, directory: id.url, scrollbackLines: scrollbackLines)
            tab.onExit = { [weak self] tab, code in self?.shellExited(tab, code: code, in: id) }
            tab.screen.onOpenFile = { [weak self] url, line, column in self?.onOpenFile?(url, line, column) }
            tab.start(clock: clock)
            let tabID = tab.id
            processes.register(RunningProcesses.Entry(
                id: tabID,
                kind: .terminal,
                window: window,
                workspace: id,
                pid: session.pid,
                title: { [weak tab] in tab?.displayTitle ?? "" },
                show: { [weak self] in self?.onShowTab?(tabID, id) }
            ))
            tabsByWorkspace[id, default: []].append(tab)
            activeByWorkspace[id] = tab.id
            if self.workspace?.id == id {
                setOpen(true)
                focusRequest += 1
            }
        } catch {
            spawnFailure = switch error {
            case .openFailed(let code): "The system would not make a terminal (error \(code))."
            case .spawnFailed(let code): "Couldn\u{2019}t start \(spec.executable): \(String(cString: strerror(code)))."
            }
        }
    }

    /// Brings a shell forward in `workspace`, which the window is showing or
    /// on its way to: the panel opens with the tab in front, and takes the
    /// keyboard once it is on screen.
    public func reveal(_ id: UUID, in workspace: WorkspaceID) {
        guard tabsByWorkspace[workspace]?.contains(where: { $0.id == id }) == true else { return }
        activeByWorkspace[workspace] = id
        if self.workspace?.id == workspace {
            setOpen(true)
            focusRequest += 1
        } else {
            pendingReveal = workspace
        }
    }

    func select(_ tab: TerminalTab) {
        guard let workspace, tabs.contains(where: { $0.id == tab.id }) else { return }
        activeByWorkspace[workspace.id] = tab.id
        focusRequest += 1
    }

    /// Names a tab, or with a blank name lets it follow what is running again.
    /// Hands the keyboard back to the terminal: the name was typed over it.
    func rename(_ tab: TerminalTab, to name: String) {
        tab.rename(to: name)
        select(tab)
    }

    /// Pins a tab or lets it go. Pinned tabs sit together at the front, in the
    /// order they were pinned; the rest keep their order behind them. The tab
    /// showing stays the one showing.
    func togglePin(_ tab: TerminalTab) {
        guard let id = workspace(holding: tab), var tabs = tabsByWorkspace[id],
              let index = tabs.firstIndex(where: { $0.id == tab.id })
        else { return }
        tab.setPinned(!tab.isPinned)
        TabOrder.repin(&tabs, at: index, isPinned: \.isPinned)
        tabsByWorkspace[id] = tabs
    }

    /// Puts a tab at `index`, on its own side of the pinned tabs. The tab
    /// showing stays the one showing.
    func move(_ tab: TerminalTab, to index: Int) {
        guard let id = workspace(holding: tab), var tabs = tabsByWorkspace[id],
              let from = tabs.firstIndex(where: { $0.id == tab.id })
        else { return }
        if TabOrder.move(&tabs, from: from, to: index, isPinned: \.isPinned) { tabsByWorkspace[id] = tabs }
    }

    private func workspace(holding tab: TerminalTab) -> WorkspaceID? {
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

    /// Closes the tab showing, asking first if it is running something. An
    /// idle shell goes without a question.
    public func requestCloseActiveTab() async {
        if let tab = activeTab { await requestClose(tab) }
    }

    func requestClose(_ tab: TerminalTab) async {
        guard let command = await tab.runningCommand() else {
            close(tab)
            return
        }
        closePrompt = ClosePrompt(tabID: tab.id, command: command)
    }

    /// Carries out the answer to ``closePrompt``.
    func answerClose(confirm: Bool) {
        guard let prompt = closePrompt else { return }
        closePrompt = nil
        // The tab may have finished or gone while the question was up.
        guard confirm, let tab = tabsByWorkspace.values.joined().first(where: { $0.id == prompt.tabID }) else { return }
        close(tab)
    }

    /// Ends a shell and takes its tab away. The one beside it comes forward,
    /// and the panel goes when it was the last.
    func close(_ tab: TerminalTab) {
        guard let id = workspace(holding: tab) else { return }
        tab.terminate()
        remove(tab, from: id)
    }

    private func remove(_ tab: TerminalTab, from id: WorkspaceID) {
        processes.unregister(tab.id)
        guard var tabs = tabsByWorkspace[id], let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        tabsByWorkspace[id] = tabs.isEmpty ? nil : tabs
        if activeByWorkspace[id] == tab.id {
            activeByWorkspace[id] = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
        if tabs.isEmpty, workspace?.id == id { setOpen(false) }
        else if workspace?.id == id { focusRequest += 1 }
    }

    /// A shell went by itself. A clean exit takes its tab with it; anything
    /// else stays up with the reason, until a key is pressed.
    private func shellExited(_ tab: TerminalTab, code: Int32, in id: WorkspaceID) {
        processes.unregister(tab.id)
        if code == 0 {
            remove(tab, from: id)
            return
        }
        tab.screen.announce("[Process exited with code \(code)]")
        tab.screen.onKeyWhileEnded = { [weak self, weak tab] in
            guard let self, let tab else { return }
            remove(tab, from: id)
        }
    }

    func dismissSpawnFailure() {
        spawnFailure = nil
    }

    // MARK: Letting go

    /// Any shell is open in any workspace of this window, so closing the window
    /// has something to end.
    public var hasTerminals: Bool {
        tabsByWorkspace.values.contains { !$0.isEmpty }
    }

    /// What every shell of this window is running, for the window and quit
    /// prompts. Empty when they are all idle.
    public func runningCommands() async -> [String] {
        var commands: [String] = []
        for tab in tabsByWorkspace.values.joined() {
            if let command = await tab.runningCommand() { commands.append(command) }
        }
        return commands
    }

    /// Ends every shell for a workspace this window has stopped keeping.
    public func discard(_ id: WorkspaceID) {
        for tab in tabsByWorkspace[id] ?? [] {
            tab.terminate()
            processes.unregister(tab.id)
        }
        tabsByWorkspace[id] = nil
        activeByWorkspace[id] = nil
        if workspace?.id == id { isOpen = false }
    }

    /// Ends every shell: the window is closing.
    public func terminateAll() {
        for tabs in tabsByWorkspace.values {
            for tab in tabs {
                tab.terminate()
                processes.unregister(tab.id)
            }
        }
        tabsByWorkspace = [:]
        activeByWorkspace = [:]
    }
}
