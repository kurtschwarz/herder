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
    let open: WindowAgentSessions
    let commands = StubCommandClient()
    let processes = RunningProcesses()
    static let lookup = "opencode session list --format json -n 20"
    let root = URL(filePath: "/code/api")
    let other = URL(filePath: "/code/web")

    init() {
        catalog = AgentCatalog(state: InMemoryStateStore())
        open = WindowAgentSessions(store: AgentSessions(state: state, clock: clock))
    }

    func makeRegistry() -> WorkspaceRegistry {
        WorkspaceRegistry(files: files, git: git, watcher: watcher, clock: clock, state: state)
    }

    func makeModel() -> AgentPanelModel {
        AgentPanelModel(
            pty: pty,
            commands: commands,
            clock: SleepingClock(),
            catalog: catalog,
            sessions: open,
            processes: processes,
            environment: ["SHELL": "/bin/sh"],
            sampleInterval: .milliseconds(10)
        )
    }

    func workspace(_ url: URL, in registry: WorkspaceRegistry) async throws -> Workspace {
        try #require(await registry.open(WorkspaceID(url)))
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

    @Test func aPlanSessionRunsThePlanCommand() async throws {
        let (model, _, _) = try await shown()

        await model.startSession(mode: .plan)

        let id = try #require(model.activeTab?.id).uuidString.lowercased()
        let spec = try #require(pty.specs.last)
        #expect(spec.arguments.last == "exec claude --session-id \(id) --permission-mode plan")
        #expect(model.activeTab?.mode == .plan)
    }

    @Test func aRequestedSessionKeepsItsModeUntilItsWorkspaceShows() async throws {
        let registry = makeRegistry()
        let model = makeModel()
        await model.show(try await workspace(root, in: registry))

        model.requestSession(in: WorkspaceID(other), mode: .plan)
        await model.show(try await workspace(other, in: registry))

        #expect(model.activeTab?.mode == .plan)
        #expect(pty.specs.last?.arguments.last?.hasSuffix("--permission-mode plan") == true)
    }

    @Test func aTabRestoredFromBeforeModesIsBuild() async throws {
        let registry = makeRegistry()
        let workspace = try await workspace(root, in: registry)
        let old = #"{"tabs":[{"id":"\#(UUID().uuidString)","agent":{"id":"claude-code","name":"Claude Code","command":"claude"},"number":1}]}"#
        try workspace.uiState(AgentPanelUIState.self).restore(from: Data(old.utf8))

        let model = makeModel()
        await model.show(workspace)

        #expect(model.tabs.first?.mode == .build)
    }

    @Test func aRestoredTabThatStartsFreshKeepsItsMode() async throws {
        let registry = makeRegistry()
        let workspace = try await workspace(root, in: registry)
        let agent = Agent(id: "x", name: "X", command: "x", planCommand: "x --plan", resumeCommand: "x --resume")
        let id = UUID()
        workspace.uiState(AgentPanelUIState.self).tabs = [
            AgentPanelUIState.Tab(id: id, agent: agent, number: 1, mode: .plan),
        ]
        let model = makeModel()
        await model.show(workspace)

        #expect(model.tabs.first?.mode == .plan)
        let saved = try workspace.uiState(AgentPanelUIState.self).encode()
        let again = AgentPanelUIState()
        try again.restore(from: saved)
        #expect(again.tabs.first?.mode == .plan)
    }

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

    /// opencode's colours are set for the panel alone, so a person's own
    /// terminals keep whatever theme they chose there.
    @Test func anAgentsOwnEnvironmentReachesItsTerminal() async throws {
        let (model, _, _) = try await shown()
        await model.startSession(try #require(catalog.agent("opencode")))
        await model.startSession(try #require(catalog.agent("codex")))

        let opencode = try #require(pty.specs.first?.environment["OPENCODE_CLI_CONFIG_CONTENT"])
        #expect(opencode.contains("\"herder\""))
        #expect(pty.specs.last?.environment["OPENCODE_CLI_CONFIG_CONTENT"] == nil)
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

    @Test func aCustomAgentsEnvironmentBeatsTheApps() async throws {
        let (model, _, _) = try await shown()
        var aider = catalog.add()
        aider.command = "aider"
        aider.environment = ["SHELL": "/bin/custom", "ANTHROPIC_BASE_URL": "http://localhost:4000"]
        catalog.update(aider)

        await model.startSession(aider)

        let environment = try #require(pty.specs.last?.environment)
        #expect(environment["ANTHROPIC_BASE_URL"] == "http://localhost:4000")
        #expect(environment["SHELL"] == "/bin/custom")
    }

    @Test func anEditToACustomAgentsEnvironmentReachesATabThatIsAlreadyOpen() async throws {
        let (model, _, _) = try await shown()
        var aider = catalog.add()
        aider.command = "aider"
        catalog.update(aider)
        await model.startSession(aider)
        let tab = try #require(model.activeTab)

        aider.environment = ["ANTHROPIC_BASE_URL": "http://localhost:4000"]
        catalog.update(aider)
        await model.reattach(tab)

        #expect(pty.specs.last?.environment["ANTHROPIC_BASE_URL"] == "http://localhost:4000")
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

    @Test func aSessionIsClosedFromOutsideThePanel() async throws {
        let (model, _, _) = try await shown(sessions: 2)
        let first = model.tabs[0]

        model.close(first.id)

        #expect(pty.sessions[0].wasTerminated)
        #expect(model.tabs.map(\.id) == [model.activeTab?.id])
        #expect(!model.tabs.contains { $0.id == first.id })
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

        model.activeTab?.screen?.send(text: "hello\r")
        pty.sessions[0].emit("\u{1b}]0;\u{2733} Fix the build\u{07}")

        try await eventually("the title arrives") { open.sessions(in: workspace.id).first?.title == "Fix the build" }
        withExtendedLifetime(model) {}
    }

    @Test func theRootStatusTitleNamesItBeforeTheTerminalTitle() async throws {
        let (model, workspace, _) = try await shown(sessions: 1)

        model.activeTab?.screen?.send(text: "hello\r")
        pty.sessions[0].emit("\u{1b}]0;OC | Old\u{07}")
        try await eventually("the terminal title arrives") { open.sessions(in: workspace.id).first?.title == "OC | Old" }

        // "✳ Fix the build", as base64: a label, so its mark stays.
        let label = Data("\u{2733} Fix the build".utf8).base64EncodedString()
        pty.sessions[0].emit("\u{1b}]7501;state=idle:title=\(label)\u{07}")

        try await eventually("the label arrives") { open.sessions(in: workspace.id).first?.title == "\u{2733} Fix the build" }
        withExtendedLifetime(model) {}
    }

    @Test func aTitleOnlyAChildRecordHasDoesNotNameIt() async throws {
        let (model, workspace, _) = try await shown(sessions: 1)

        let label = Data("Build".utf8).base64EncodedString()
        model.activeTab?.screen?.send(text: "hello\r")
        pty.sessions[0].emit("\u{1b}]0;Fix the build\u{07}")
        pty.sessions[0].emit("\u{1b}]7501;id=build:state=working:title=\(label)\u{07}")

        try await eventually("the report arrives") { model.activeTab?.screen?.programStatuses.isEmpty == false }
        try await eventually("the title arrives") { open.sessions(in: workspace.id).first?.title == "Fix the build" }
        withExtendedLifetime(model) {}
    }

    @Test func onlyAReportedStatusIsBelieved() async throws {
        let (model, workspace, _) = try await shown(sessions: 1)

        // Output, a bell, a notification and progress say nothing.
        pty.sessions[0].emit("thinking\u{07}\u{1b}]9;Claude needs your permission\u{07}\u{1b}]9;4;3\u{07}")
        try await eventually("it is written") { model.activeTab?.screen?.outputCount ?? 0 > 0 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(open.sessions(in: workspace.id).first?.state == .idle)

        pty.sessions[0].emit("\u{1b}]7501;state=working\u{07}")
        try await eventually("it works") { open.sessions(in: workspace.id).first?.state == .working }
    }

    @Test func aReportedStatusIsBelievedOverTheOutput() async throws {
        let (model, workspace, _) = try await shown(sessions: 1)
        let message = Data("Edit main.swift?".utf8).base64EncodedString()

        pty.sessions[0].emit("\u{1b}]7501;state=blocked:kind=permission:msg=\(message)\u{07}")
        try await eventually("it asks") {
            open.sessions(in: workspace.id).first?.state == .needsInput("Edit main.swift?")
        }

        // Typing does not answer it: only the program can say it has moved on.
        model.activeTab?.screen?.send(text: "y")
        pty.sessions[0].emit("\u{1b}]7501;state=working\u{07}")
        try await eventually("it works") { open.sessions(in: workspace.id).first?.state == .working }

        // Idle while it redraws, because it says so.
        pty.sessions[0].emit("\u{1b}]7501;state=idle\u{07}redrawn")
        try await eventually("it rests") { open.sessions(in: workspace.id).first?.state == .idle }
    }

    @Test func aRedrawIsNotActivityForAProgramThatReportsItsStatus() async throws {
        let (model, workspace, _) = try await shown(sessions: 1)
        func lastActivity() -> Date? { open.sessions(in: workspace.id).first?.live?.lastActivity }

        pty.sessions[0].emit("\u{1b}]7501;state=idle\u{07}")
        try await eventually("it rests") { model.activeTab?.screen?.programStatuses.isEmpty == false }
        try await Task.sleep(for: .milliseconds(50))
        let rested = try #require(lastActivity())

        // What it draws when another session on the worktree edits a file.
        pty.sessions[0].emit("redrawn")
        try await eventually("it is written") { model.activeTab?.screen?.outputCount ?? 0 > 1 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(lastActivity() == rested)

        pty.sessions[0].emit("\u{1b}]7501;state=working\u{07}")
        try await eventually("it works") { (lastActivity() ?? .distantPast) > rested }
    }

    @Test func anyOutputIsActivityForAProgramThatSaysNothing() async throws {
        let (model, workspace, _) = try await shown(sessions: 1)
        func lastActivity() -> Date? { open.sessions(in: workspace.id).first?.live?.lastActivity }
        try await eventually("it is listed") { lastActivity() != nil }
        let opened = try #require(lastActivity())

        pty.sessions[0].emit("thinking")

        try await eventually("it is active") { (lastActivity() ?? .distantPast) > opened }
        withExtendedLifetime(model) {}
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

    // MARK: Naming

    @Test func aNamedTabSaysItsNameInTheTabAndTheSidebar() async throws {
        let (model, _, _) = try await shown(sessions: 2)
        let tab = model.tabs[0]

        model.rename(tab, to: "  Fix the build  ")

        #expect(model.tabs.map { model.title(of: $0) } == ["Fix the build", "Claude Code 2"])
        #expect(open.sessions.first?.title == "Fix the build")
        #expect(model.activeTab?.id == tab.id)
    }

    @Test func aBlankNameGoesBackToTheAgents() async throws {
        let (model, _, _) = try await shown(sessions: 1)
        let tab = try #require(model.activeTab)
        model.rename(tab, to: "Fix the build")

        model.rename(tab, to: "   ")

        #expect(model.title(of: tab) == "Claude Code")
    }

    @Test func aNameIsRememberedWithItsTab() async throws {
        let registry = makeRegistry()
        let model = makeModel()
        let workspace = try await workspace(root, in: registry)
        await model.show(workspace)
        await model.startSession()
        model.rename(try #require(model.activeTab), to: "Fix the build")
        model.terminateAll()
        await workspace.saveSnapshot()

        let reopened = makeModel()
        await reopened.show(try await self.workspace(root, in: makeRegistry()))

        #expect(reopened.activeTab.map { reopened.title(of: $0) } == "Fix the build")
    }

    // MARK: Saved state from before the tab bar went

    @Test func savedTabsStillLoadWithAPinnedFieldNobodyReadsAnyMore() throws {
        let tab = AgentPanelUIState.Tab(
            id: UUID(), agent: try #require(Agent.presets.first), number: 2, name: "Fix the build",
            session: nil, started: nil
        )
        var stored = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(tab)) as? [String: Any]
        )
        // As an earlier build wrote it.
        stored["pinned"] = true
        let data = try JSONSerialization.data(withJSONObject: ["tabs": [stored], "active": tab.id.uuidString])

        let state = AgentPanelUIState()
        try state.restore(from: data)

        #expect(state.tabs == [tab])
        #expect(state.active == tab.id)
    }

    @Test func theSubjectIsTheNameThenTheProgramTitleThenTheAgentsName() async throws {
        let (model, _, _) = try await shown(sessions: 1)
        let tab = try #require(model.activeTab)
        #expect(model.subject(of: tab) == model.title(of: tab))

        model.rename(tab, to: "Fix the build")
        #expect(model.subject(of: tab) == "Fix the build")
    }

    // MARK: Agents that name their own sessions

    /// What opencode's lookup prints for sessions in `root`, made now.
    func answerLookup(with ids: [String], in url: URL? = nil) {
        let now = Date().timeIntervalSince1970 * 1000
        let entries = ids.enumerated().map { index, id in
            #"{"id": "\#(id)", "created": \#(now + Double(index)), "directory": "\#((url ?? root).path)"}"#
        }
        commands.answer(Self.lookup, with: "[" + entries.joined(separator: ",") + "]")
    }

    @Test func anOpencodeSessionIsLookedUpAndResumedByItsOwnId() async throws {
        _ = try await closedWindow(starting: ["opencode"], selecting: 0)
        answerLookup(with: ["ses_abc"])

        let model = makeModel()
        await model.show(try await workspace(root, in: makeRegistry()))

        #expect(commands.calls.map(\.line) == [Self.lookup])
        #expect(commands.calls.first?.directory == root)
        #expect(pty.specs.last?.arguments.last == "exec opencode -s ses_abc")
        #expect(model.activeTab?.sessionID == "ses_abc")
    }

    @Test func theIdFoundIsRememberedSoTheNextReopenNeedsNoLookup() async throws {
        _ = try await closedWindow(starting: ["opencode"], selecting: 0)
        answerLookup(with: ["ses_abc"])
        let registry = makeRegistry()
        let first = makeModel()
        let workspace = try await workspace(root, in: registry)
        await first.show(workspace)
        first.terminateAll()
        await workspace.saveSnapshot()
        commands.answer(Self.lookup, with: "[]")

        let model = makeModel()
        await model.show(try await self.workspace(root, in: makeRegistry()))

        #expect(pty.specs.last?.arguments.last == "exec opencode -s ses_abc")
    }

    /// A tab saved before a preset's environment changed still gets the
    /// current one: a preset's environment is Herder's, not the person's.
    @Test func aSavedPresetTabResumesWithThePresetsCurrentEnvironment() async throws {
        _ = try await closedWindow(starting: ["opencode"], selecting: 0)
        let key = WorkspaceSnapshot.persistenceKey(for: WorkspaceID(root))
        var snapshot = try #require(try await state.load(WorkspaceSnapshot.self, forKey: key))
        let panel = AgentPanelUIState()
        try panel.restore(from: try #require(snapshot.uiState[AgentPanelUIState.persistenceKey]))
        panel.tabs[0].agent.environment = nil
        snapshot.uiState[AgentPanelUIState.persistenceKey] = try panel.encode()
        try await state.save(snapshot, forKey: key)

        let model = makeModel()
        await model.show(try await workspace(root, in: makeRegistry()))

        #expect(pty.specs.last?.environment["OPENCODE_CLI_CONFIG_CONTENT"] != nil)
    }

    @Test func anOpencodeSessionThatCannotBeFoundStartsAfresh() async throws {
        _ = try await closedWindow(starting: ["opencode"], selecting: 0)

        let model = makeModel()
        await model.show(try await workspace(root, in: makeRegistry()))

        #expect(pty.specs.last?.arguments.last == "exec opencode")
    }

    @Test func twoOpencodeTabsInOneWorktreeEachKeepTheirOwnSession() async throws {
        _ = try await closedWindow(starting: ["opencode", "opencode"], selecting: 0)
        answerLookup(with: ["ses_first", "ses_second"])

        let model = makeModel()
        await model.show(try await workspace(root, in: makeRegistry()))
        model.select(model.tabs[1])

        try await eventually("the second resumes") { pty.specs.last?.arguments.last == "exec opencode -s ses_second" }
        #expect(model.tabs.map(\.sessionID) == ["ses_first", "ses_second"])
    }

    @Test func aSessionInAnotherWorktreeIsNotTaken() async throws {
        _ = try await closedWindow(starting: ["opencode"], selecting: 0)
        answerLookup(with: ["ses_web"], in: other)

        let model = makeModel()
        await model.show(try await workspace(root, in: makeRegistry()))

        #expect(pty.specs.last?.arguments.last == "exec opencode")
    }

    @Test func theSessionIsLookedUpWhenItsFirstTurnEnds() async throws {
        let (model, _, _) = try await shown()
        await model.startSession(try #require(catalog.agent("opencode")))
        answerLookup(with: ["ses_live"])

        // Working, then quiet.
        pty.sessions[0].emit("thinking…")
        try await eventually("it is looked up") { model.activeTab?.sessionID == "ses_live" }
    }

    @Test func aReplyThatArrivesWithTheTypingStillTriggersTheLookup() async throws {
        let (model, _, _) = try await shown()
        await model.startSession(try #require(catalog.agent("opencode")))
        answerLookup(with: ["ses_quick"])

        // The Enter and the whole reply inside one sample, then quiet.
        model.activeTab?.screen?.send(text: "hello\r")
        pty.sessions[0].emit("Hi! How can I help?")
        try await eventually("it is looked up") { model.activeTab?.sessionID == "ses_quick" }
    }

    @Test func agentsThatTakeAnIdUpFrontAreNeverLookedUp() async throws {
        _ = try await closedWindow(starting: ["claude-code"], selecting: 0)

        let model = makeModel()
        await model.show(try await workspace(root, in: makeRegistry()))

        #expect(commands.calls.isEmpty)
    }

    // MARK: The Task Manager's list

    @Test func aStartedSessionIsListedWithItsProcess() async throws {
        let (model, _, _) = try await shown(sessions: 1)

        let tab = try #require(model.activeTab)
        let entry = try #require(processes.entry(tab.id))
        #expect(entry.kind == .agentSession)
        #expect(entry.pid == pty.sessions[0].pid)
        #expect(entry.workspace == WorkspaceID(root))
        #expect(entry.window == open.window)
        #expect(entry.title() == model.subject(of: tab))
    }

    @Test func aSessionThatFailedToStartIsListedWithoutAProcess() async throws {
        pty.failSpawns(with: .openFailed(1))

        let (model, _, _) = try await shown(sessions: 1)

        let tab = try #require(model.activeTab)
        let entry = try #require(processes.entry(tab.id))
        #expect(entry.pid == nil)
        #expect(entry.state() == .failed)
    }

    @Test func aRestoredTabIsListedPausedBeforeAnythingStarts() async throws {
        let ids = try await closedWindow(starting: ["claude-code", "codex"], selecting: 0)
        #expect(processes.entries.isEmpty)

        let model = makeModel()
        model.restore(try await workspace(root, in: makeRegistry()))

        #expect(Set(processes.entries.map(\.id)) == Set(ids))
        #expect(processes.entries.allSatisfy { $0.pid == nil && $0.state() == .paused })
        withExtendedLifetime(model) {}
    }

    @Test func aSessionIsListedWithTheStateTheSidebarReads() async throws {
        let (model, _, _) = try await shown(sessions: 1)
        let tab = try #require(model.activeTab)

        let state = try #require(processes.entry(tab.id)).state()

        #expect(state == open.sessions.first { $0.id == tab.id }?.state)
        #expect(state == .idle)
    }

    @Test func anAgentThatCrashedStaysListedWithoutAProcessUntilItsTabCloses() async throws {
        let (model, _, _) = try await shown(sessions: 1)
        let tab = try #require(model.activeTab)

        pty.sessions[0].exit(with: 1)
        try await eventually("the tab notices") { model.activeTab?.phase == .exited(1) }

        let entry = try #require(processes.entry(tab.id))
        #expect(entry.pid == nil)
        #expect(entry.state() == .exited(1))

        model.close(tab)
        #expect(processes.entry(tab.id) == nil)
    }

    @Test func aCleanExitTakesTheEntryWithTheTab() async throws {
        let (model, _, _) = try await shown(sessions: 1)
        let id = try #require(model.activeTab?.id)

        pty.sessions[0].exit(with: 0)

        try await eventually("the entry goes") { processes.entry(id) == nil }
    }

    @Test func startingAgainAfterACrashListsTheNewProcess() async throws {
        let (model, _, _) = try await shown(sessions: 1)
        let tab = try #require(model.activeTab)
        pty.sessions[0].exit(with: 1)
        try await eventually("the tab notices") { model.activeTab?.phase == .exited(1) }

        await model.reattach(tab)

        #expect(processes.entries.count == 1)
        #expect(processes.entry(tab.id)?.pid == pty.sessions[1].pid)
    }

    @Test func closingTheWindowOrAWorkspaceTakesTheEntriesAway() async throws {
        let (model, workspace, _) = try await shown(sessions: 2)
        #expect(processes.entries.count == 2)

        model.discard(workspace.id)
        #expect(processes.entries.isEmpty)

        let (second, _, _) = try await shown(sessions: 1)
        second.terminateAll()
        #expect(processes.entries.isEmpty)
    }

    @Test func showingFromTheTaskManagerAsksTheWindow() async throws {
        let (model, workspace, _) = try await shown(sessions: 1)
        let tab = try #require(model.activeTab)
        // CONCURRENCY: set and read on the main actor, by a closure that is not marked as running there.
        nonisolated(unsafe) var asked: (UUID, WorkspaceID)?
        model.onShowTab = { asked = ($0, $1) }

        processes.entry(tab.id)?.show()

        #expect(asked?.0 == tab.id)
        #expect(asked?.1 == workspace.id)
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
