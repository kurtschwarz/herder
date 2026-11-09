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
    let catalog = AgentCatalog(state: InMemoryStateStore())
    let history: SessionHistory
    let root = URL(filePath: "/code/api")

    init() {
        history = SessionHistory(git: git, state: state, clock: clock)
    }

    var repository: PathKey { PathKey(root) }

    func shown() async throws -> AgentPanelModel {
        let registry = WorkspaceRegistry(files: files, git: git, watcher: watcher, clock: clock, state: state)
        let model = AgentPanelModel(
            pty: pty, commands: StubCommandClient(), clock: VirtualClockClient(), catalog: catalog,
            openSessions: OpenAgentSessions(), history: history,
            environment: ["SHELL": "/bin/sh"], sampleInterval: .seconds(3600)
        )
        await model.show(try #require(await registry.open(WorkspaceID(root))))
        return model
    }

    func eventually(_ what: String, _ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("never happened: \(what)")
    }

    func started(_ agent: Agent? = nil) async throws -> (AgentPanelModel, SessionHistoryRecord) {
        let model = try await shown()
        await model.startSession(agent)
        let id = try #require(model.activeTab?.id)
        try await eventually("it is written down") { history.record(id) != nil }
        return (model, try #require(history.record(id)))
    }

    @Test func aSessionIsWrittenDownWhenItsAgentStarts() async throws {
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

        #expect(history.record(record.id)?.endReason == .closed)
        #expect(history.ended(in: repository).map(\.id) == [record.id])
    }

    @Test func theAgentQuittingEndsIt() async throws {
        let (model, record) = try await started()

        pty.sessions[0].exit(with: 0)

        try await eventually("it ends") { history.record(record.id)?.endReason == .exited }
        #expect(model.tabs.isEmpty)
    }

    @Test func aCrashLeavesItOpen() async throws {
        let (model, record) = try await started()

        pty.sessions[0].exit(with: 1)
        try await eventually("the tab notices") { model.activeTab?.phase == .exited(1) }

        #expect(history.record(record.id)?.endedAt == nil)
    }

    @Test func aSessionPickedUpAgainIsTheSameRecordInANewTab() async throws {
        let (model, record) = try await started()
        model.closeActiveTab()
        let ended = try #require(history.record(record.id))

        await model.resume(ended)

        let tab = try #require(model.activeTab)
        #expect(tab.id == record.id)
        #expect(pty.specs.last?.arguments.last == "exec claude --resume \(record.id.uuidString.lowercased())")
        let again = try #require(history.record(record.id))
        #expect(again.endedAt == nil)
        #expect(again.startedAt == record.startedAt)
        #expect(history.repositories[repository]?.count == 1)
    }

    @Test func aSessionWithNoIDIsNotPickedUp() async throws {
        let codex = try #require(Agent.presets.first { $0.id == "codex" })
        let (model, record) = try await started(codex)
        model.closeActiveTab()
        let specs = pty.specs.count

        await model.resume(try #require(history.record(record.id)))

        // Not `codex resume --last`, which may be another session.
        #expect(pty.specs.count == specs)
        #expect(model.tabs.isEmpty)
        #expect(history.record(record.id)?.endedAt != nil)
    }

    @Test func aSessionOfAnAgentThatIsGoneIsNotPickedUp() async throws {
        let (model, record) = try await started()
        model.closeActiveTab()
        var orphan = try #require(history.record(record.id))
        orphan.agentID = "custom-deleted"

        await model.resume(orphan)

        #expect(model.tabs.isEmpty)
    }
}
