import Foundation
import TestSupport
import Testing

@testable import Core

@Suite @MainActor struct AgentCatalogTests {
    let state = InMemoryStateStore()

    @Test func thePresetsComeFirstAndClaudeCodeIsTheDefault() {
        let catalog = AgentCatalog(state: state)

        #expect(catalog.agents.map(\.command) == ["claude", "codex", "opencode", "pi"])
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

        #expect(catalog.agent("claude-code")?.command == "claude")
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
}
