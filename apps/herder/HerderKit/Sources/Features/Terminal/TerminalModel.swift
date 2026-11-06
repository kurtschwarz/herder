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

    public private(set) var workspace: Workspace?

    private var tabsByWorkspace: [WorkspaceID: [TerminalTab]] = [:]
    private var activeByWorkspace: [WorkspaceID: UUID] = [:]

    /// The panel is showing for the workspace being shown.
    public private(set) var isOpen = false

    /// What the user dragged the panel to, if they have.
    private(set) var storedHeight: CGFloat?

    /// Changes when the panel should take the keyboard.
    public private(set) var focusRequest = 0

    /// Why the last shell would not start, until it is dismissed.
    public private(set) var spawnFailure: String?

    static let limits = PanelHeight.Limits(
        defaultHeight: Theme.Size.defaultTerminalHeight,
        minimumPanel: Theme.Size.minTerminalHeight,
        minimumEditor: Theme.Size.minEditorHeight
    )

    public init(
        pty: any PTYClient,
        clock: any ClockClient,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
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
            let tab = TerminalTab(session: session, size: spec.size, directory: id.url)
            tab.onExit = { [weak self] tab, code in self?.shellExited(tab, code: code, in: id) }
            tab.start(clock: clock)
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

    func select(_ tab: TerminalTab) {
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

    /// Ends a shell and takes its tab away. The one beside it comes forward,
    /// and the panel goes when it was the last.
    func close(_ tab: TerminalTab) {
        guard let id = tabsByWorkspace.first(where: { $0.value.contains { $0.id == tab.id } })?.key else { return }
        tab.terminate()
        remove(tab, from: id)
    }

    private func remove(_ tab: TerminalTab, from id: WorkspaceID) {
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

    /// Ends every shell for a workspace this window has stopped keeping.
    public func discard(_ id: WorkspaceID) {
        for tab in tabsByWorkspace[id] ?? [] { tab.terminate() }
        tabsByWorkspace[id] = nil
        activeByWorkspace[id] = nil
        if workspace?.id == id { isOpen = false }
    }

    /// Ends every shell: the window is closing.
    public func terminateAll() {
        for tabs in tabsByWorkspace.values {
            for tab in tabs { tab.terminate() }
        }
        tabsByWorkspace = [:]
        activeByWorkspace = [:]
    }
}
