import Core
import Foundation
import TestSupport
import Testing

@testable import AgentSessionsFeature

/// The panel's sessions and whether it shows, against a PTY the test plays
/// both ends of.
@Suite(.timeLimit(.minutes(1))) struct AgentPanelModelTests {
    let files = InMemoryFileClient()
    let git = StubGitClient()
    let watcher = StubFileWatcherClient()
    let clock = VirtualClockClient()
    let state = InMemoryStateStore()
    let pty = StubPTYClient()
    let catalog: AgentCatalog
    let open = OpenAgentSessions()
    let root = URL(filePath: "/code/api")
    let other = URL(filePath: "/code/web")

    init() {
        catalog = AgentCatalog(state: InMemoryStateStore())
    }

    func makeRegistry() -> WorkspaceRegistry {
        WorkspaceRegistry(files: files, git: git, watcher: watcher, clock: clock, state: state)
    }

    func makeModel() -> AgentPanelModel {
        AgentPanelModel(
            pty: pty,
            clock: SleepingClock(),
            catalog: catalog,
            openSessions: open,
            environment: ["SHELL": "/bin/sh"],
            sampleInterval: .milliseconds(10)
        )
    }

    func workspace(_ url: URL, in registry: WorkspaceRegistry) async throws -> Workspace {
        try #require(await registry.open(WorkspaceID(url)))
    }

    func eventually(_ what: String, _ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("never happened: \(what)")
    }

    /// A model showing `root`, with `count` sessions started.
    func shown(sessions count: Int = 0) async throws -> (AgentPanelModel, Workspace, WorkspaceRegistry) {
        let registry = makeRegistry()
        let model = makeModel()
        let workspace = try await workspace(root, in: registry)
        await model.show(workspace)
        for _ in 0..<count { await model.startSession() }
        return (model, workspace, registry)
    }

    // MARK: Starting

    @Test func aSessionIsTheAgentsCommandInTheWorktreeRoot() async throws {
        let (model, _, _) = try await shown(sessions: 1)

        let spec = try #require(pty.specs.last)
        #expect(spec.executable == "/bin/sh")
        let id = try #require(model.activeTab?.id).uuidString.lowercased()
        #expect(spec.arguments == ["/bin/sh", "-l", "-i", "-c", "exec claude --session-id \(id)"])
        #expect(spec.workingDirectory == root)
        #expect(model.activeTab?.phase == .running)
    }

    @Test func eachSessionIsAFreshProcessAndTheNewestComesForward() async throws {
        let (model, _, _) = try await shown(sessions: 2)

        #expect(pty.specs.count == 2)
        #expect(model.tabs.map { model.title(of: $0) } == ["Claude Code", "Claude Code 2"])
        #expect(model.activeTab?.number == 2)
    }

    @Test func aProcessThatCannotStartSaysWhy() async throws {
        let (model, _, _) = try await shown()
        pty.failSpawns(with: .spawnFailed(ENOENT))

        await model.startSession()

        guard case .failed(let reason)? = model.activeTab?.phase else {
            Issue.record("expected a failure, got \(String(describing: model.activeTab?.phase))")
            return
        }
        #expect(reason.contains("/bin/sh"))
    }

    @Test func eachAgentRunsItsOwnCommandAndIsNumberedApart() async throws {
        let (model, _, _) = try await shown()
        let codex = try #require(catalog.agent("codex"))
        let pi = try #require(catalog.agent("pi"))

        await model.startSession(codex)
        await model.startSession(pi)
        await model.startSession(codex)

        let commands = pty.specs.compactMap { $0.arguments.last?.split(separator: " ").prefix(2).joined(separator: " ") }
        #expect(commands == ["exec codex", "exec pi", "exec codex"])
        #expect(model.tabs.map { model.title(of: $0) } == ["Codex", "Pi", "Codex 2"])
    }

    @Test func theAgentUsedLastIsTheOneStartedWhenNobodySays() async throws {
        let (model, _, _) = try await shown()
        await model.startSession(try #require(catalog.agent("opencode")))

        await model.startSession()

        #expect(catalog.lastUsed.id == "opencode")
        #expect(pty.specs.last?.arguments.last == "exec opencode")
    }

    @Test func aCustomAgentRunsAsTyped() async throws {
        let (model, _, _) = try await shown()
        var aider = catalog.add()
        aider.name = "Aider"
        aider.command = "aider --model sonnet"
        catalog.update(aider)

        await model.startSession(aider)

        #expect(pty.specs.last?.arguments.last == "exec aider --model sonnet")
        #expect(model.activeTab.map { model.title(of: $0) } == "Aider")
    }

    @Test func anAgentWithNoCommandStartsNothing() async throws {
        let (model, _, _) = try await shown()

        await model.startSession(catalog.add())

        #expect(pty.specs.isEmpty)
        #expect(model.tabs.isEmpty)
    }

    // MARK: Closing

    @Test func closingATabEndsItsProcess() async throws {
        let (model, _, _) = try await shown(sessions: 1)

        model.close(try #require(model.activeTab))

        #expect(pty.sessions[0].wasTerminated)
        #expect(model.tabs.isEmpty)
    }

    @Test func closingTheTabShowingBringsItsNeighbourForward() async throws {
        let (model, _, _) = try await shown(sessions: 3)
        model.select(model.tabs[1])

        model.closeActiveTab()

        #expect(model.activeTab?.number == 3)
    }

    @Test func quittingTheTerminalUIClosesItsTab() async throws {
        let (model, _, _) = try await shown(sessions: 1)

        pty.sessions[0].exit(with: 0)

        try await eventually("the tab goes") { model.tabs.isEmpty }
    }

    @Test func aCrashKeepsTheTabAndAReattachStartsItAgain() async throws {
        let (model, _, _) = try await shown(sessions: 1)

        pty.sessions[0].exit(with: 1)
        try await eventually("the tab notices") { model.activeTab?.phase == .exited(1) }
        #expect(model.tabs.count == 1)

        let tab = try #require(model.activeTab)
        await model.reattach(tab)

        #expect(pty.specs.count == 2)
        // It has a conversation now, so starting it again picks that up.
        #expect(pty.specs.last?.arguments.last == "exec claude --resume \(tab.id.uuidString.lowercased())")
        #expect(model.activeTab?.phase == .running)
    }

    // MARK: Workspaces

    @Test func switchingAwayAndBackKeepsTheProcessRunning() async throws {
        let (model, first, registry) = try await shown(sessions: 1)

        await model.show(try await workspace(other, in: registry))
        #expect(model.tabs.isEmpty)
        await model.show(first)

        #expect(model.tabs.count == 1)
        #expect(pty.specs.count == 1)
        #expect(!pty.sessions[0].wasTerminated)
    }

    @Test func aSessionAskedForInAnotherWorkspaceStartsWhenItIsShown() async throws {
        let (model, _, registry) = try await shown()
        let web = try await workspace(other, in: registry)

        model.requestSession(in: web.id)
        #expect(pty.specs.isEmpty)
        await model.show(web)

        #expect(model.tabs.count == 1)
        #expect(pty.specs.last?.workingDirectory == other)
    }

    @Test func theAgentAskedForElsewhereIsTheOneThatStarts() async throws {
        let (model, _, registry) = try await shown()
        let web = try await workspace(other, in: registry)

        model.requestSession(in: web.id, agent: try #require(catalog.agent("pi")))
        await model.show(web)

        #expect(pty.specs.last?.arguments.last?.hasPrefix("exec pi --session-id ") == true)
    }

    @Test func aRequestForAWorkspaceThatNeverCameStartsNothingInAnotherOne() async throws {
        let (model, first, _) = try await shown()

        model.requestSession(in: WorkspaceID(other))
        await model.show(first)
        await model.show(first)

        #expect(model.tabs.isEmpty)
    }

    @Test func discardingAWorkspaceEndsItsProcesses() async throws {
        let (model, workspace, _) = try await shown(sessions: 1)

        model.discard(workspace.id)

        #expect(pty.sessions[0].wasTerminated)
        #expect(model.tabs.isEmpty)
    }

    // MARK: Showing

    @Test func showingAWorktreeStartsNothingByItself() async throws {
        let (model, _, registry) = try await shown()

        await model.show(try await workspace(other, in: registry))

        #expect(model.tabs.isEmpty)
        #expect(pty.specs.isEmpty)
    }

    // MARK: Cycling

    @Test func tabsCycleInBothDirections() async throws {
        let (model, _, _) = try await shown(sessions: 2)
        #expect(model.canSelectOtherTab)

        model.selectNextTab()
        #expect(model.activeTab?.number == 1)
        model.selectPreviousTab()
        #expect(model.activeTab?.number == 2)
    }

    // MARK: Telling the sidebar

    @Test func openSessionsAreListedForTheirWorktree() async throws {
        let (model, workspace, registry) = try await shown(sessions: 2)
        await model.show(try await self.workspace(other, in: registry))
        await model.startSession(try #require(catalog.agent("pi")))

        #expect(open.sessions(in: workspace.id).map(\.title) == ["Claude Code", "Claude Code 2"])
        #expect(open.sessions(in: WorkspaceID(other)).map(\.agentName) == ["Pi"])
        #expect(open.focused == model.activeTab?.id)
    }

    @Test func closingASessionTakesItOffTheList() async throws {
        let (model, workspace, _) = try await shown(sessions: 1)

        model.closeActiveTab()

        #expect(open.sessions(in: workspace.id).isEmpty)
    }

    @Test func theTitleTheProgramGivesItselfNamesItWithoutItsSpinner() async throws {
        // Held to the end: the model is what samples the screen and hears the
        // exit, and nothing else keeps it alive.
        let (model, workspace, _) = try await shown(sessions: 1)

        pty.sessions[0].emit("\u{1b}]0;\u{2733} Fix the build\u{07}")

        try await eventually("the title arrives") { open.sessions(in: workspace.id).first?.title == "Fix the build" }
        withExtendedLifetime(model) {}
    }

    @Test func aNotificationNeedsInputUntilSomethingIsTyped() async throws {
        let (model, workspace, _) = try await shown(sessions: 1)

        pty.sessions[0].emit("\u{1b}]9;Claude needs your permission\u{07}")
        try await eventually("it asks") {
            open.sessions(in: workspace.id).first?.state == .needsInput("Claude needs your permission")
        }

        model.activeTab?.screen?.send(text: "y")
        try await eventually("the answer clears it") {
            open.sessions(in: workspace.id).first?.state != .needsInput("Claude needs your permission")
        }
    }

    @Test func aCrashIsListedWithItsStatus() async throws {
        // Held to the end: the model is what samples the screen and hears the
        // exit, and nothing else keeps it alive.
        let (model, workspace, _) = try await shown(sessions: 1)

        pty.sessions[0].exit(with: 2)

        try await eventually("it is marked") { open.sessions(in: workspace.id).first?.state == .exited(2) }
        withExtendedLifetime(model) {}
    }

    @Test func revealingASessionInAnotherWorkspaceBringsItForwardThere() async throws {
        let (model, first, registry) = try await shown(sessions: 2)
        let wanted = try #require(model.tabs.first)
        let web = try await workspace(other, in: registry)
        await model.show(web)

        model.reveal(wanted.id, in: first.id)
        let before = model.focusRequest
        await model.show(first)

        #expect(model.activeTab?.id == wanted.id)
        #expect(model.focusRequest > before)
        #expect(open.focused == wanted.id)
    }

    // MARK: Resuming

    /// Starts sessions in `root` in one window and closes it, as a person
    /// quitting does: the tabs are remembered, the processes end.
    func closedWindow(starting agents: [String], selecting index: Int) async throws -> [UUID] {
        let registry = makeRegistry()
        let model = makeModel()
        let workspace = try await workspace(root, in: registry)
        await model.show(workspace)
        for id in agents { await model.startSession(try #require(catalog.agent(id))) }
        model.select(model.tabs[index])
        let ids = model.tabs.map(\.id)
        model.terminateAll()
        await workspace.saveSnapshot()
        return ids
    }

    @Test func reopeningResumesTheSessionInFrontAndPausesTheRest() async throws {
        let ids = try await closedWindow(starting: ["claude-code", "codex"], selecting: 0)
        let before = pty.specs.count

        let model = makeModel()
        await model.show(try await workspace(root, in: makeRegistry()))

        #expect(model.tabs.map(\.id) == ids)
        #expect(model.activeTab?.id == ids[0])
        #expect(pty.specs.count == before + 1)
        #expect(pty.specs.last?.arguments.last == "exec claude --resume \(ids[0].uuidString.lowercased())")
        #expect(model.tabs[1].phase == .waiting)
        #expect(open.sessions.map(\.state).last == .paused)
    }

    @Test func aPausedSessionResumesWhenItIsClicked() async throws {
        _ = try await closedWindow(starting: ["claude-code", "codex"], selecting: 0)
        let model = makeModel()
        await model.show(try await workspace(root, in: makeRegistry()))

        model.select(model.tabs[1])

        try await eventually("codex resumes") { pty.specs.last?.arguments.last == "exec codex resume --last" }
        #expect(model.tabs.map { model.title(of: $0) } == ["Claude Code", "Codex"])
    }

    @Test func aWorkspaceHeldButNotShownIsListedWithoutStartingAnything() async throws {
        _ = try await closedWindow(starting: ["claude-code"], selecting: 0)
        let before = pty.specs.count

        let model = makeModel()
        model.restore(try await workspace(root, in: makeRegistry()))

        #expect(open.sessions(in: WorkspaceID(root)).map(\.state) == [.paused])
        #expect(pty.specs.count == before)
        withExtendedLifetime(model) {}
    }

    @Test func aClosedTabIsForgotten() async throws {
        let registry = makeRegistry()
        let model = makeModel()
        let workspace = try await workspace(root, in: registry)
        await model.show(workspace)
        await model.startSession()
        model.closeActiveTab()
        await workspace.saveSnapshot()

        let reopened = makeModel()
        await reopened.show(try await self.workspace(root, in: makeRegistry()))

        #expect(reopened.tabs.isEmpty)
    }

    @Test func numberingCarriesOnFromTheRememberedSessions() async throws {
        _ = try await closedWindow(starting: ["codex", "codex"], selecting: 0)
        let model = makeModel()
        await model.show(try await workspace(root, in: makeRegistry()))

        await model.startSession(try #require(catalog.agent("codex")))

        #expect(model.tabs.map { model.title(of: $0) } == ["Codex", "Codex 2", "Codex 3"])
    }
}

/// A clock that really waits. The sampler loops for as long as a session is
/// open, and against ``VirtualClockClient``, whose sleeps return at once, every
/// model alive in the suite would spin on the main actor and starve the rest.
private struct SleepingClock: ClockClient {
    var now: ContinuousClock.Instant { .now }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
