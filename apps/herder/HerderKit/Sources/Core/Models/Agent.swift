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

    /// Stands for the session's id in a command. Herder mints the id, a UUID,
    /// so an agent that can be told its id up front is resumed exactly; one
    /// that cannot is resumed however its own resume command says.
    public static let sessionToken = "{session}"

    public init(id: ID, name: String, command: String, resumeCommand: String? = nil) {
        self.id = id
        self.name = name
        self.command = command
        self.resumeCommand = resumeCommand
    }

    /// The command line to run for `session`: a new one, or picking one up.
    public func commandLine(for session: UUID, resuming: Bool) -> String {
        let template = resuming ? (resumeCommand.flatMap { $0.isEmpty ? nil : $0 } ?? command) : command
        return template.replacing(Self.sessionToken, with: session.uuidString.lowercased())
    }

    /// The agents Herder knows how to start without being told. Never
    /// change an id: it is what a saved "last used" names.
    ///
    /// Claude Code and Pi can be given a session's id up front, so they resume
    /// exactly. Codex and opencode cannot: they resume the last session in the
    /// worktree, which is the right one unless several were open at once.
    public static let presets: [Agent] = [
        Agent(
            id: "claude-code",
            name: "Claude Code",
            command: "claude --session-id \(sessionToken)",
            resumeCommand: "claude --resume \(sessionToken)"
        ),
        Agent(id: "codex", name: "Codex", command: "codex", resumeCommand: "codex resume --last"),
        Agent(id: "opencode", name: "opencode", command: "opencode", resumeCommand: "opencode --continue"),
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
