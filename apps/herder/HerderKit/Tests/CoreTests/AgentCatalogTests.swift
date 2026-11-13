import Foundation
import TestSupport
import Testing

@testable import Core

@Suite @MainActor struct AgentCatalogTests {
    let state = InMemoryStateStore()

    @Test func thePresetsComeFirstAndClaudeCodeIsTheDefault() {
        let catalog = AgentCatalog(state: state)

        #expect(catalog.agents.map(\.program) == ["claude", "codex", "opencode", "pi"])
        #expect(catalog.lastUsed.id == "claude-code")
    }

    @Test func theAgentUsedLastAndTheUsersOwnSurviveARelaunch() async throws {
        let catalog = AgentCatalog(state: state)
        var mine = catalog.add()
        mine.name = "Aider"
        mine.command = "aider"
        catalog.update(mine)
        catalog.markUsed(mine)
        await catalog.flushSaves()

        let relaunched = AgentCatalog(state: state)
        await relaunched.load()

        #expect(relaunched.custom == [mine])
        #expect(relaunched.lastUsed == mine)
    }

    @Test func aCustomAgentsEnvironmentSurvivesARelaunch() async throws {
        let catalog = AgentCatalog(state: state)
        var mine = catalog.add()
        mine.command = "opencode"
        mine.environment = ["ANTHROPIC_BASE_URL": "http://localhost:4000"]
        catalog.update(mine)
        await catalog.flushSaves()

        let relaunched = AgentCatalog(state: state)
        await relaunched.load()

        #expect(relaunched.agent(mine.id)?.environment == ["ANTHROPIC_BASE_URL": "http://localhost:4000"])
    }

    @Test func removingTheAgentUsedLastFallsBackToTheDefault() {
        let catalog = AgentCatalog(state: state)
        let mine = catalog.add()
        catalog.markUsed(mine)

        catalog.remove(mine.id)

        #expect(catalog.custom.isEmpty)
        #expect(catalog.lastUsed.id == "claude-code")
    }

    @Test func aPresetCannotBeEditedOrRemoved() throws {
        let catalog = AgentCatalog(state: state)
        var claude = try #require(catalog.agent("claude-code"))
        claude.command = "rm -rf ~"

        catalog.update(claude)
        catalog.remove(claude.id)

        #expect(catalog.agent("claude-code") == Agent.presets[0])
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
