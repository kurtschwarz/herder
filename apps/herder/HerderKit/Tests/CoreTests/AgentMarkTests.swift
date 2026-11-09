import Core
import Testing

@Suite struct AgentMarkTests {
    @Test func anOrphanMarkedWithItsOwnPidIsALeftover() {
        #expect(AgentMark.isLeftover(pid: 4242, parent: 1, environment: [AgentMark.variable: "4242"]))
    }

    @Test func oneWhoseHerderIsStillRunningIsNot() {
        #expect(!AgentMark.isLeftover(pid: 4242, parent: 900, environment: [AgentMark.variable: "4242"]))
    }

    /// Started by the agent, and detached by it on purpose.
    @Test func oneThatInheritedTheMarkIsNot() {
        #expect(!AgentMark.isLeftover(pid: 5000, parent: 1, environment: [AgentMark.variable: "4242"]))
    }

    @Test func anUnmarkedOrphanIsNot() {
        #expect(!AgentMark.isLeftover(pid: 4242, parent: 1, environment: ["PATH": "/bin"]))
    }
}
