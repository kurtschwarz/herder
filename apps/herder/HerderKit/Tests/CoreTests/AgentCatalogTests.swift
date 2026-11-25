import Foundation
import TestSupport
import Testing

@testable import Core

@Suite @MainActor struct AgentCatalogTests {
    let state = InMemoryStateStore()
    let file = InMemorySettingsFileClient()

    func makeCatalog() -> AgentCatalog {
        AgentCatalog(state: state, settings: UserSettingsStore(file: file, clock: VirtualClockClient()))
    }

    /// The same snapshots and the same settings file under a second app.
    func relaunch() async -> AgentCatalog {
        let settings = UserSettingsStore(file: file, clock: VirtualClockClient())
        await settings.load()
        let catalog = AgentCatalog(state: state, settings: settings)
        await catalog.load()
        return catalog
    }

    @Test func thePresetsComeFirstAndClaudeCodeIsTheDefault() {
        let catalog = makeCatalog()

        #expect(catalog.agents.map(\.program) == ["claude", "codex", "opencode", "pi"])
        #expect(catalog.lastUsed.id == "claude-code")
    }

    @Test func theAgentUsedLastAndTheUsersOwnSurviveARelaunch() async throws {
        let catalog = makeCatalog()
        var mine = catalog.add()
        mine.name = "Aider"
        mine.command = "aider"
        catalog.update(mine)
        catalog.markUsed(mine)
        await catalog.flushSaves()

        let relaunched = await relaunch()

        #expect(relaunched.custom == [mine])
        #expect(relaunched.lastUsed == mine)
    }

    @Test func aCustomAgentsEnvironmentSurvivesARelaunch() async throws {
        let catalog = makeCatalog()
        var mine = catalog.add()
        mine.command = "opencode"
        mine.environment = ["ANTHROPIC_BASE_URL": "http://localhost:4000"]
        catalog.update(mine)
        await catalog.flushSaves()

        let relaunched = await relaunch()

        #expect(relaunched.agent(mine.id)?.environment == ["ANTHROPIC_BASE_URL": "http://localhost:4000"])
    }

    @Test func removingTheAgentUsedLastFallsBackToTheDefault() {
        let catalog = makeCatalog()
        let mine = catalog.add()
        catalog.markUsed(mine)

        catalog.remove(mine.id)

        #expect(catalog.custom.isEmpty)
        #expect(catalog.lastUsed.id == "claude-code")
    }

    @Test func aPresetCannotBeEditedOrRemoved() throws {
        let catalog = makeCatalog()
        var claude = try #require(catalog.agent("claude-code"))
        claude.command = "rm -rf ~"

        catalog.update(claude)
        catalog.remove(claude.id)

        #expect(catalog.agent("claude-code") == Agent.presets[0])
    }

    @Test func theUsersAgentsGoToTheSettingsFileAndTheAgentUsedLastToTheState() async throws {
        let catalog = makeCatalog()
        var mine = catalog.add(named: "My Aider")
        mine.command = "aider"
        catalog.update(mine)
        catalog.markUsed(mine)
        await catalog.flushSaves()

        #expect(mine.id == "my-aider")
        let written = try UserSettings.decode(try #require(file.contents))
        #expect(written.customAgents == [mine])
        let snapshot = try #require(try await state.load(AgentsSnapshot.self, forKey: AgentsSnapshot.persistenceKey))
        #expect(snapshot.lastUsed == "my-aider")
        #expect(snapshot.custom.isEmpty)
    }

    @Test func anAddedAgentsIDIsMadeFromItsNameAndKeptThroughARename() {
        let catalog = makeCatalog()
        let first = catalog.add(named: "Aider")
        let second = catalog.add(named: "Aider")
        var renamed = first
        renamed.name = "Something else"
        catalog.update(renamed)

        #expect(first.id == "aider")
        #expect(second.id == "aider-2")
        #expect(catalog.custom.map(\.id) == ["aider", "aider-2"])
    }

    @Test func anIDMintedBeforeTheSettingsFileStillFindsItsAgent() async {
        file.edit(#"{"agents":{"custom":[{"id":"custom-6f9619ff-8b86","name":"Aider","command":"aider"}]}}"#)
        let catalog = await relaunch()

        #expect(catalog.agent("custom-6F9619FF-8B86")?.name == "Aider")
    }

    @Test func aSnapshotFromBeforeAnyAgentWasAddedStillReads() throws {
        let decoded = try JSONDecoder().decode(AgentsSnapshot.self, from: Data(#"{"version":1}"#.utf8))

        #expect(decoded == AgentsSnapshot())
    }

    @Test func theProgramIsTheCommandsFirstWord() {
        #expect(Agent(id: "x", name: "", command: "aider --model sonnet").program == "aider")
        #expect(Agent(id: "x", name: "", command: "aider").displayName == "aider")
        #expect(!Agent(id: "x", name: "Empty", command: "  ").isRunnable)
    }

    @Test func aSessionsIdGoesWhereTheCommandAsksForIt() throws {
        let claude = try #require(Agent.presets.first { $0.id == "claude-code" })
        let opencode = try #require(Agent.presets.first { $0.id == "opencode" })

        #expect(claude.commandLine(session: "6f9619ff", resuming: false) == "claude --session-id 6f9619ff")
        #expect(claude.commandLine(session: "6f9619ff", resuming: true) == "claude --resume 6f9619ff")
        #expect(opencode.commandLine(session: "ses_abc", resuming: false) == "opencode")
        #expect(opencode.commandLine(session: "ses_abc", resuming: true) == "opencode -s ses_abc")
        #expect(opencode.looksUpSessions)
        #expect(!claude.looksUpSessions)
    }

    @Test func anAgentWithNoResumeCommandStartsAfresh() {
        let agent = Agent(id: "x", name: "Aider", command: "aider", resumeCommand: "")

        #expect(agent.commandLine(session: "x", resuming: true) == "aider")
    }

    @Test func anAgentSavedBeforeResumingExistedStillReads() throws {
        let decoded = try JSONDecoder().decode(
            Agent.self, from: Data(#"{"id":"custom-1","name":"Aider","command":"aider"}"#.utf8)
        )

        #expect(decoded == Agent(id: "custom-1", name: "Aider", command: "aider"))
    }

    // MARK: Modes

    @Test func planRunsThePlanCommandWhereAnAgentHasOne() throws {
        let claude = try #require(Agent.presets.first { $0.id == "claude-code" })

        #expect(claude.commandLine(session: "6f9619ff", resuming: false, mode: .plan)
            == "claude --session-id 6f9619ff --permission-mode plan")
        #expect(claude.commandLine(session: "6f9619ff", resuming: false, mode: .build)
            == "claude --session-id 6f9619ff")
    }

    @Test func planWithNoPlanCommandRunsTheNormalOne() throws {
        for id in ["codex", "pi"] {
            let agent = try #require(Agent.presets.first { $0.id == id })
            #expect(agent.planCommand == nil)
            #expect(agent.commandLine(session: "x", resuming: false, mode: .plan)
                == agent.commandLine(session: "x", resuming: false, mode: .build))
        }
        #expect(Agent(id: "x", name: "", command: "aider", planCommand: "  ")
            .commandLine(session: "x", resuming: false, mode: .plan) == "aider")
    }

    @Test func resumingIgnoresTheMode() throws {
        let claude = try #require(Agent.presets.first { $0.id == "claude-code" })

        #expect(claude.commandLine(session: "6f9619ff", resuming: true, mode: .plan)
            == claude.commandLine(session: "6f9619ff", resuming: true, mode: .build))
        #expect(claude.commandLine(session: "6f9619ff", resuming: true, mode: .plan) == "claude --resume 6f9619ff")
    }

    @Test func aCustomAgentKeepsItsPlanCommandThroughTheSnapshot() throws {
        let snapshot = AgentsSnapshot(custom: [Agent(id: "custom-1", name: "Aider", command: "aider", planCommand: "aider --architect")])
        let decoded = try JSONDecoder().decode(AgentsSnapshot.self, from: JSONEncoder().encode(snapshot))

        #expect(decoded == snapshot)
    }
}
