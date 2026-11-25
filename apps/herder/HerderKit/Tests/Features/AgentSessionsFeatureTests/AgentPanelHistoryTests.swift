import Core
import Foundation
import TestSupport
import Testing

@testable import AgentSessionsFeature

/// What the panel writes into the session history as sessions start and end,
/// and what it does with one picked up from it.
@Suite(.timeLimit(.minutes(1))) struct AgentPanelHistoryTests {
    let files = InMemoryFileClient()
    let git = StubGitClient()
    let watcher = StubFileWatcherClient()
    let clock = VirtualClockClient()
    let state = InMemoryStateStore()
    let pty = StubPTYClient()
    let catalog = AgentCatalog(state: InMemoryStateStore(), settings: .inMemory())
    let sessions: AgentSessions
    let root = URL(filePath: "/code/api")

    init() {
        sessions = AgentSessions(state: state, clock: clock)
    }

    var repository: PathKey { PathKey(root) }

    func shown() async throws -> AgentPanelModel {
        let registry = WorkspaceRegistry(files: files, git: git, watcher: watcher, clock: clock, state: state)
        let model = AgentPanelModel(
            pty: pty, commands: StubCommandClient(), clock: VirtualClockClient(), catalog: catalog,
            sessions: WindowAgentSessions(store: sessions),
            environment: ["SHELL": "/bin/sh"], sampleInterval: .seconds(3600)
        )
        await model.show(try #require(await registry.open(WorkspaceID(root))))
        return model
    }


    func started(_ agent: Agent? = nil) async throws -> (AgentPanelModel, AgentSession) {
        let model = try await shown()
        await model.startSession(agent)
        let id = try #require(model.activeTab?.id)
        model.activeTab?.screen?.send(text: "hello\r")
        try await eventually("it is written down") { sessions.recorded(in: repository).contains { $0.id == id } }
        return (model, try #require(sessions.session(id)))
    }

    /// A tab remembered from before there was a history has no record. It
    /// gets one once it is said something to after it resumes, keeping when
    /// it first started.
    @Test func aTabRestoredWithNoRecordIsWrittenDownWhenItIsSaidSomethingTo() async throws {
        let registry = WorkspaceRegistry(files: files, git: git, watcher: watcher, clock: clock, state: state)
        let workspace = try #require(await registry.open(WorkspaceID(root)))
        let id = UUID()
        let started = Date(timeIntervalSince1970: 1_000_000)
        let claude = try #require(Agent.presets.first { $0.id == "claude-code" })
        workspace.uiState(AgentPanelUIState.self).tabs = [
            AgentPanelUIState.Tab(id: id, agent: claude, number: 1, started: started),
        ]
        let model = AgentPanelModel(
            pty: pty, commands: StubCommandClient(), clock: VirtualClockClient(), catalog: catalog,
            sessions: WindowAgentSessions(store: sessions), environment: ["SHELL": "/bin/sh"], sampleInterval: .seconds(3600)
        )

        await model.show(workspace)
        model.activeTab?.screen?.send(text: "hello\r")

        try await eventually("it is written down") { sessions.recorded(in: repository).contains { $0.id == id } }
        let session = try #require(sessions.session(id))
        #expect(session.startedAt == started)
        #expect(session.sessionID == id.uuidString.lowercased())
        #expect(model.sessions.sessions.map(\.id) == [id])
    }

    @Test func aTabThatNeverStartedIsListedButNotWrittenDown() async throws {
        let model = try await shown()
        pty.failSpawns(with: .spawnFailed(2))

        await model.startSession()

        let id = try #require(model.activeTab?.id)
        #expect(model.sessions.sessions.map(\.id) == [id])
        #expect(model.sessions.sessions.first?.state == .failed)
        #expect(sessions.session(id) == nil)
    }

    @Test func aTabLeftAloneIsListedButNotWrittenDown() async throws {
        let model = try await shown()

        await model.startSession()
        let id = try #require(model.activeTab?.id)
        // Typing without Return is not saying anything yet.
        model.activeTab?.screen?.send(text: "hel")
        await sessions.flushSaves()

        #expect(model.sessions.sessions.map(\.id) == [id])
        #expect(sessions.session(id) == nil)
    }

    @Test func closingATabLeftAloneLeavesNoHistory() async throws {
        let model = try await shown()
        await model.startSession()

        model.closeActiveTab()
        await sessions.flushSaves()

        #expect(sessions.recorded(in: repository).isEmpty)
    }

    @Test func aSessionIsWrittenDownWhenItIsFirstSaidSomethingTo() async throws {
        let (model, record) = try await started()

        #expect(record.id == model.activeTab?.id)
        #expect(record.agentID == "claude-code")
        #expect(record.agentName == "Claude Code")
        #expect(record.worktree == WorkspaceID(root))
        #expect(record.sessionID == record.id.uuidString.lowercased())
        #expect(record.endedAt == nil)
    }

    @Test func anAgentThatGivesNoIDHasNoneRecorded() async throws {
        let codex = try #require(Agent.presets.first { $0.id == "codex" })

        let (_, record) = try await started(codex)

        #expect(record.sessionID == nil)
    }

    @Test func closingTheTabEndsIt() async throws {
        let (model, record) = try await started()

        model.closeActiveTab()

        #expect(sessions.session(record.id)?.endReason == .closed)
        #expect(sessions.ended(in: repository).map(\.id) == [record.id])
    }

    @Test func theAgentQuittingEndsIt() async throws {
        let (model, record) = try await started()

        pty.sessions[0].exit(with: 0)

        try await eventually("it ends") { sessions.session(record.id)?.endReason == .exited }
        #expect(model.tabs.isEmpty)
    }

    @Test func aCrashLeavesItOpen() async throws {
        let (model, record) = try await started()

        pty.sessions[0].exit(with: 1)
        try await eventually("the tab notices") { model.activeTab?.phase == .exited(1) }

        #expect(sessions.session(record.id)?.endedAt == nil)
    }

    /// Opens `record`, ended, in a new tab, as clicking it in the sidebar does.
    func reading(_ model: AgentPanelModel, _ record: AgentSession) async throws -> AgentSession {
        model.closeActiveTab()
        let ended = try #require(sessions.session(record.id))
        await model.resume(ended)
        return ended
    }

    @Test func theSessionInFrontIsEndedWhileItIsReadAndNotOnceItReopens() async throws {
        let (model, record) = try await started()
        #expect(model.endedSessionNotice == nil)

        _ = try await reading(model, record)
        #expect(model.endedSessionNotice == .worktreeKept)

        model.activeTab?.screen?.send(text: "hello again\r")
        try await eventually("it reopens") { sessions.session(record.id)?.isEnded == false }
        #expect(model.endedSessionNotice == nil)
    }

    @Test func aSessionWhoseWorktreeIsGoneIsReadInAnotherAndSaysSo() async throws {
        let (model, record) = try await started()
        model.closeActiveTab()
        let ended = try #require(sessions.session(record.id))
        let registry = WorkspaceRegistry(files: files, git: git, watcher: watcher, clock: clock, state: state)
        let other = URL(filePath: "/code/api-main")
        await model.show(try #require(await registry.open(WorkspaceID(other))))

        await model.resume(ended, in: WorkspaceID(other))

        #expect(model.activeTab?.id == record.id)
        #expect(pty.specs.last?.workingDirectory == other)
        #expect(pty.specs.last?.arguments.last == "exec claude --resume \(record.id.uuidString.lowercased())")
        #expect(model.endedSessionNotice == .worktreeRemoved(agent: "Claude Code", carriedOnIn: "api-main"))

        model.activeTab?.screen?.send(text: "hello again\r")
        try await eventually("it reopens") { sessions.session(record.id)?.isEnded == false }
        #expect(model.endedSessionNotice == nil)
    }

    @Test func readingAnEndedSessionOpensItsTabAndLeavesItEnded() async throws {
        let (model, record) = try await started()
        let ended = try await reading(model, record)

        let tab = try #require(model.activeTab)
        #expect(tab.id == record.id)
        #expect(pty.specs.last?.arguments.last == "exec claude --resume \(record.id.uuidString.lowercased())")
        #expect(sessions.session(record.id) == ended)
        #expect(sessions.recorded(in: repository).count == 1)
        // Listed by the window, but not as one in progress.
        #expect(model.sessions.sessions.map(\.id) == [record.id])
        #expect(model.sessions.sessionsByRecency.isEmpty)
        #expect(model.sessions.sessions(in: WorkspaceID(root)).isEmpty)
    }

    @Test func theAgentWorkingOrAskingInAReadingTabDoesNotReopenIt() async throws {
        let (model, record) = try await started()
        let ended = try await reading(model, record)

        let screen = try #require(model.activeTab?.screen)
        screen.send(text: "scrolling\u{1B}[A")
        await model.show(model.workspace)
        await sessions.flushSaves()

        #expect(sessions.session(record.id) == ended)
    }

    @Test func returnInAReadingTabReopensItAndKeepsItsStart() async throws {
        let (model, record) = try await started()
        _ = try await reading(model, record)

        model.activeTab?.screen?.send(text: "go on\r")

        try await eventually("it reopens") { sessions.session(record.id)?.endedAt == nil }
        let again = try #require(sessions.session(record.id))
        #expect(again.endReason == nil)
        #expect(again.startedAt == record.startedAt)
        #expect(model.sessions.sessionsByRecency.map(\.id) == [record.id])
        #expect(sessions.recorded(in: repository).count == 1)
    }

    @Test func closingAReadingTabKeepsTheOriginalEnd() async throws {
        let (model, record) = try await started()
        let ended = try await reading(model, record)

        model.closeActiveTab()

        #expect(sessions.session(record.id) == ended)
        #expect(model.tabs.isEmpty)
    }

    @Test func theAgentQuittingInAReadingTabKeepsTheOriginalEnd() async throws {
        let (model, record) = try await started()
        let ended = try await reading(model, record)

        pty.sessions.last?.exit(with: 0)

        try await eventually("the tab goes") { model.tabs.isEmpty }
        #expect(sessions.session(record.id) == ended)
    }

    @Test func readingASessionWhoseTabIsOpenBringsItForward() async throws {
        let (model, record) = try await started()
        let ended = try await reading(model, record)
        let other = try #require(Agent.presets.first { $0.id == "claude-code" })
        await model.startSession(other)
        #expect(model.activeTab?.id != record.id)
        let specs = pty.specs.count

        await model.resume(ended)

        #expect(model.activeTab?.id == record.id)
        #expect(model.tabs.filter { $0.id == record.id }.count == 1)
        #expect(pty.specs.count == specs)
        #expect(sessions.session(record.id) == ended)
    }

    @Test func aSessionBeingReadCannotBeDeletedButCanBeRenamed() async throws {
        let (model, record) = try await started()
        _ = try await reading(model, record)

        sessions.delete(record.id)
        sessions.rename(record.id, to: "Scroll fix")
        model.rename(record.id, to: "Scroll fix")

        #expect(sessions.session(record.id) != nil)
        #expect(sessions.session(record.id)?.name == "Scroll fix")
        #expect(sessions.session(record.id)?.endedAt != nil)
        #expect(model.title(of: try #require(model.activeTab)) == "Scroll fix")

        model.closeActiveTab()
        sessions.delete(record.id)
        #expect(sessions.session(record.id) == nil)
    }

    @Test func aSessionPickedUpAgainIsTheSameRecordInANewTab() async throws {
        let (model, record) = try await started()
        _ = try await reading(model, record)
        model.activeTab?.screen?.send(text: "go on\r")

        try await eventually("it reopens") { sessions.session(record.id)?.endedAt == nil }
        #expect(sessions.session(record.id)?.startedAt == record.startedAt)
        #expect(sessions.recorded(in: repository).count == 1)
    }

    @Test func aSessionRenamedInTheHistoryKeepsItsNameWhenPickedUp() async throws {
        let (model, record) = try await started()
        model.closeActiveTab()
        sessions.rename(record.id, to: "Scroll fix")

        await model.resume(try #require(sessions.session(record.id)))

        let tab = try #require(model.activeTab)
        #expect(model.title(of: tab) == "Scroll fix")
        #expect(sessions.session(record.id)?.name == "Scroll fix")
    }

    @Test func aTabsNameIsWrittenDown() async throws {
        let (model, record) = try await started()

        model.rename(try #require(model.activeTab), to: "Scroll fix")

        #expect(sessions.session(record.id)?.name == "Scroll fix")
        #expect(sessions.session(record.id)?.title == "Scroll fix")
    }

    @Test func aRunningSessionIsRenamedFromOutsideThePanel() async throws {
        let (model, record) = try await started()
        let focus = model.focusRequest

        model.rename(record.id, to: "Scroll fix")

        #expect(model.activeTab?.customName == "Scroll fix")
        #expect(model.sessions.sessions.first?.title == "Scroll fix")
        #expect(sessions.session(record.id)?.name == "Scroll fix")
        // The sidebar asked: the keyboard stays where it is.
        #expect(model.focusRequest == focus)
    }

    // MARK: Titles of sessions picked up again

    /// A session titled "Fix the build" by its program, ended and read in a new tab.
    func titledAndReading() async throws -> (AgentPanelModel, AgentSession) {
        let (model, record) = try await started()
        let label = Data("Fix the build".utf8).base64EncodedString()
        pty.sessions[0].emit("\u{1b}]7501;state=idle:title=\(label)\u{07}")
        try await eventually("the title is written down") { sessions.session(record.id)?.title == "Fix the build" }
        return (model, try await reading(model, record))
    }

    func terminalTitle(of model: AgentPanelModel, is title: String) async throws {
        pty.sessions.last?.emit("\u{1b}]0;\(title)\u{07}")
        try await eventually("the terminal title arrives") { model.activeTab?.screen?.title == title }
    }

    @Test func aTerminalTitleDoesNotRenameASessionNobodyHasSpokenTo() async throws {
        let (model, ended) = try await titledAndReading()

        try await terminalTitle(of: model, is: "OpenCode")
        await model.show(model.workspace)
        await sessions.flushSaves()

        #expect(sessions.session(ended.id) == ended)
        #expect(model.subject(of: try #require(model.activeTab)) == "Fix the build")
    }

    @Test func aSessionStartingAgainIsCalledWhatItWasBeforeItSaysAnything() async throws {
        let (model, _) = try await titledAndReading()

        let tab = try #require(model.activeTab)
        #expect(model.subject(of: tab) == "Fix the build")
    }

    @Test func aTerminalTitleRenamesASessionOnceThePersonHasSpoken() async throws {
        let (model, record) = try await titledAndReading()

        model.activeTab?.screen?.send(text: "go on\r")
        try await terminalTitle(of: model, is: "Ship it")

        try await eventually("it is renamed") { sessions.session(record.id)?.title == "Ship it" }
        #expect(model.subject(of: try #require(model.activeTab)) == "Ship it")
    }

    @Test func aTitleTheProgramReportsRenamesASessionWithoutAnyTyping() async throws {
        let (model, record) = try await titledAndReading()

        let label = Data("Ship it".utf8).base64EncodedString()
        pty.sessions.last?.emit("\u{1b}]7501;state=idle:title=\(label)\u{07}")

        try await eventually("it is renamed") { sessions.session(record.id)?.title == "Ship it" }
        #expect(model.subject(of: try #require(model.activeTab)) == "Ship it")
    }

    @Test func aNameThePersonGaveBeatsTheProgramsTitle() async throws {
        let (model, record) = try await titledAndReading()
        model.rename(record.id, to: "Scroll fix")

        let label = Data("Ship it".utf8).base64EncodedString()
        pty.sessions.last?.emit("\u{1b}]7501;state=idle:title=\(label)\u{07}")
        try await eventually("the label arrives") { model.activeTab?.programTitle == "Ship it" }

        #expect(model.subject(of: try #require(model.activeTab)) == "Scroll fix")
        #expect(sessions.session(record.id)?.title == "Scroll fix")
    }

    @Test func aSessionWithNoIDIsNotPickedUp() async throws {
        let codex = try #require(Agent.presets.first { $0.id == "codex" })
        let (model, record) = try await started(codex)
        model.closeActiveTab()
        let specs = pty.specs.count

        await model.resume(try #require(sessions.session(record.id)))

        // Not `codex resume --last`, which may be another session.
        #expect(pty.specs.count == specs)
        #expect(model.tabs.isEmpty)
        #expect(sessions.session(record.id)?.endedAt != nil)
    }

    @Test func aSessionOfAnAgentThatIsGoneIsNotPickedUp() async throws {
        let (model, record) = try await started()
        model.closeActiveTab()
        var orphan = try #require(sessions.session(record.id))
        orphan.agentID = "custom-deleted"

        await model.resume(orphan)

        #expect(model.tabs.isEmpty)
    }
}
