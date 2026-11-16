import Foundation

/// How an agent Herder started is told apart from every other process, once
/// Herder is gone and nothing else remembers it.
///
/// Herder ends its agents when it closes them or quits, but a crash or a
/// SIGKILL ends Herder first, and an agent that ignores the hang-up then
/// runs on with no window. So each agent is started with ``variable`` set to
/// its own pid, and at launch one that has it and has lost its parent is a
/// leftover.
///
/// Its own pid, not just a flag, because the variable is inherited: a server
/// the agent started, and detached on purpose, has it too, but with the
/// agent's pid rather than its own.
public enum AgentMark {
    public static let variable = "HERDER_AGENT_PID"

    /// `parent` is 1 once whatever started the process has gone: launchd
    /// takes in every orphan. An agent of a Herder that is still running has
    /// that Herder as its parent, so a second copy of the app leaves it be.
    public static func isLeftover(pid: Int32, parent: Int32, environment: [String: String]) -> Bool {
        parent == 1 && environment[variable] == String(pid)
    }
}
