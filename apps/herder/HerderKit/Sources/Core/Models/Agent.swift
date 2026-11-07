import Foundation

/// A coding agent with a terminal UI, and the command that starts it.
///
/// Herder knows nothing about any agent beyond this: a session is the command
/// run in a terminal in a worktree's root, as the user would type it. That is
/// what lets Claude Code, Codex, opencode and Pi sit side by side, and an agent
/// nobody here has heard of be added in Settings.
public struct Agent: Codable, Sendable, Equatable, Hashable, Identifiable {
    public typealias ID = String

    /// Stable across launches: what "the agent used last" is remembered by.
    /// A preset's is its own name in code; a custom one's is minted when it
    /// is added.
    public let id: ID
    public var name: String

    /// A shell command line that starts a new session, run through the
    /// user's login shell. May name the session with ``sessionToken``.
    public var command: String

    /// The command line that picks a session up again after its terminal was
    /// closed, or `nil` for an agent that cannot: it starts afresh instead.
    /// May name the session with ``sessionToken``.
    public var resumeCommand: String?

    /// For an agent that names its own sessions: a command line that lists
    /// them, which Herder reads to learn the id of the one a tab started. See
    /// ``AgentSessionLookup`` for what it may print.
    public var sessionLookup: String?

    /// Stands for the session's id in a command. For most agents Herder mints
    /// the id, a UUID, and tells the agent; for one with a ``sessionLookup``,
    /// it is the id the agent chose, once the lookup has found it.
    public static let sessionToken = "{session}"

    public init(
        id: ID,
        name: String,
        command: String,
        resumeCommand: String? = nil,
        sessionLookup: String? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.resumeCommand = resumeCommand
        self.sessionLookup = sessionLookup
    }

    /// Whether the agent mints its own session ids, so Herder has to look
    /// them up before it can resume one.
    public var looksUpSessions: Bool {
        !(sessionLookup ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The command line to run for the session called `session`: a new one,
    /// or picking one up. Resuming with no resume command starts afresh.
    public func commandLine(session: String, resuming: Bool) -> String {
        let template = resuming ? (resumeCommand.flatMap { $0.isEmpty ? nil : $0 } ?? command) : command
        return template.replacing(Self.sessionToken, with: session)
    }

    /// The agents Herder knows how to start without being told. Never
    /// change an id: it is what a saved "last used" names.
    ///
    /// Claude Code and Pi can be given a session's id up front, so they resume
    /// exactly. opencode names its own, so its sessions are looked up and then
    /// resumed exactly. Codex can do neither here: it resumes the last session
    /// in the worktree, which is the right one unless several were open.
    public static let presets: [Agent] = [
        Agent(
            id: "claude-code",
            name: "Claude Code",
            command: "claude --session-id \(sessionToken)",
            resumeCommand: "claude --resume \(sessionToken)"
        ),
        Agent(id: "codex", name: "Codex", command: "codex", resumeCommand: "codex resume --last"),
        Agent(
            id: "opencode",
            name: "opencode",
            command: "opencode",
            resumeCommand: "opencode -s \(sessionToken)",
            sessionLookup: "opencode session list --format json -n 20"
        ),
        Agent(
            id: "pi",
            name: "Pi",
            command: "pi --session-id \(sessionToken)",
            resumeCommand: "pi --session-id \(sessionToken)"
        ),
    ]

    public var isPreset: Bool {
        Self.presets.contains { $0.id == id }
    }

    /// The program the command runs, for saying it could not be found.
    public var program: String {
        command.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? command
    }

    /// Whether there is anything to run.
    public var isRunnable: Bool {
        !command.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// What a menu calls it: its name, or something to click on when it has
    /// none.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? (isRunnable ? program : "Untitled agent") : trimmed
    }
}
