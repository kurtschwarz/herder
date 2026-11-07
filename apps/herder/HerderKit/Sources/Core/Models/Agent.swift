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

    /// A shell command line, run through the user's login shell.
    public var command: String

    public init(id: ID, name: String, command: String) {
        self.id = id
        self.name = name
        self.command = command
    }

    /// The agents Herder knows how to start without being told. Never
    /// change an id: it is what a saved "last used" names.
    public static let presets: [Agent] = [
        Agent(id: "claude-code", name: "Claude Code", command: "claude"),
        Agent(id: "codex", name: "Codex", command: "codex"),
        Agent(id: "opencode", name: "opencode", command: "opencode"),
        Agent(id: "pi", name: "Pi", command: "pi"),
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
