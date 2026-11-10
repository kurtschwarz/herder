import Core
import Foundation
import Testing

@testable import RepositoriesFeature

@Suite struct WorktreeActivityTests {
    func session(_ state: AgentSession.State?) -> AgentSession {
        AgentSession(
            id: UUID(),
            agentID: "claude-code",
            agentName: "Claude Code",
            worktree: WorkspaceID(URL(filePath: "/code/api")),
            title: "Claude Code",
            startedAt: .now,
            live: state.map { AgentSession.Live(state: $0, lastActivity: .now) }
        )
    }

    @Test func noSessionsSaysSo() {
        #expect(WorktreeActivity([]) == .none)
        #expect(WorktreeActivity([]).label == "No sessions")
    }

    @Test func workingOutranksWaitingAndIdle() {
        let activity = WorktreeActivity([session(.idle), session(.needsInput(nil)), session(.working), session(.working)])

        #expect(activity == .working(2))
        #expect(activity.label == "2 working")
    }

    @Test func waitingOutranksIdle() {
        let activity = WorktreeActivity([session(.idle), session(.needsInput("ok?"))])

        #expect(activity == .waiting(1))
        #expect(activity.label == "1 waiting")
    }

    @Test func idleIsWhatIsLeftOpen() {
        #expect(WorktreeActivity([session(.idle), session(.paused), session(.starting)]) == .idle(3))
    }

    @Test func endedTabsAreNotCounted() {
        #expect(WorktreeActivity([session(.exited(0)), session(.failed), session(nil)]) == .none)
    }
}
