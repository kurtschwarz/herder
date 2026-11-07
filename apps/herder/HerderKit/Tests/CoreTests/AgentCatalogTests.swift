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
        let id = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00CF4FC964FF"))
        let claude = try #require(Agent.presets.first { $0.id == "claude-code" })

        #expect(claude.commandLine(for: id, resuming: false) == "claude --session-id 6f9619ff-8b86-d011-b42d-00cf4fc964ff")
        #expect(claude.commandLine(for: id, resuming: true) == "claude --resume 6f9619ff-8b86-d011-b42d-00cf4fc964ff")
    }

    @Test func anAgentWithNoResumeCommandStartsAfresh() {
        let agent = Agent(id: "x", name: "Aider", command: "aider", resumeCommand: "")

        #expect(agent.commandLine(for: UUID(), resuming: true) == "aider")
    }

    @Test func anAgentSavedBeforeResumingExistedStillReads() throws {
        let decoded = try JSONDecoder().decode(
            Agent.self, from: Data(#"{"id":"custom-1","name":"Aider","command":"aider"}"#.utf8)
        )

        #expect(decoded == Agent(id: "custom-1", name: "Aider", command: "aider"))
    }
}
