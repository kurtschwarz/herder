import Foundation
import Testing

@testable import Core

@Suite struct AgentFirstPromptTests {
    private func preset(_ id: String) throws -> Agent {
        try #require(Agent.presets.first { $0.id == id })
    }

    @Test func claudeCodePlansWithThePromptLast() throws {
        #expect(try preset("claude-code").commandLine(session: "abc", resuming: false, mode: .plan, prompt: "add a minimap")
            == "claude --session-id abc --permission-mode plan 'add a minimap'")
    }

    @Test func codexTakesThePromptAsItsArgument() throws {
        #expect(try preset("codex").commandLine(session: "abc", resuming: false, mode: .plan, prompt: "add a minimap")
            == "codex 'add a minimap'")
    }

    @Test func opencodeTakesThePromptWithAFlag() throws {
        #expect(try preset("opencode").commandLine(session: "abc", resuming: false, mode: .plan, prompt: "add a minimap")
            == "opencode --prompt 'add a minimap'")
    }

    @Test func piTakesThePromptAsItsMessage() throws {
        #expect(try preset("pi").commandLine(session: "abc", resuming: false, mode: .plan, prompt: "add a minimap")
            == "pi --session-id abc 'add a minimap'")
    }

    @Test func aPromptIsQuotedSoTheShellCannotReadIt() throws {
        let line = try preset("codex").commandLine(
            session: "abc", resuming: false, mode: .plan, prompt: "it's $(rm -rf ~) `x`; \"y\"\nsecond line"
        )
        #expect(line == "codex 'it'\\''s $(rm -rf ~) `x`; \"y\"\nsecond line'")
    }

    @Test func aPromptThatStartsWithADashIsNotTakenForAnOption() throws {
        #expect(try preset("codex").commandLine(session: "abc", resuming: false, prompt: "--help me")
            == "codex -- '--help me'")
    }

    @Test func noPromptLeavesTheCommandAsItWas() throws {
        let claude = try preset("claude-code")
        #expect(claude.commandLine(session: "abc", resuming: false, mode: .plan)
            == "claude --session-id abc --permission-mode plan")
        #expect(claude.commandLine(session: "abc", resuming: false, mode: .plan, prompt: "  \n ")
            == "claude --session-id abc --permission-mode plan")
    }

    @Test func resumingNeverRepeatsThePrompt() throws {
        #expect(try preset("claude-code").commandLine(session: "abc", resuming: true, prompt: "add a minimap")
            == "claude --resume abc")
    }

    @Test func anAgentWithNoPromptArgumentStartsWithoutTheText() {
        let agent = Agent(id: "x", name: "Aider", command: "aider")
        #expect(agent.commandLine(session: "x", resuming: false, mode: .plan, prompt: "add a minimap") == "aider")
    }

    @Test func anAgentSavedBeforeFirstPromptsExistedStillReads() throws {
        let decoded = try JSONDecoder().decode(
            Agent.self, from: Data(#"{"id":"custom-1","name":"Aider","command":"aider"}"#.utf8)
        )
        #expect(decoded.promptArgument == nil)
    }
}
