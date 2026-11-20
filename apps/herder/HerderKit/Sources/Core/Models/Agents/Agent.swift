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

    /// A shell command line that starts a new session in plan mode, used in
    /// place of ``command``. `nil` for an agent with no plan flag: plan then
    /// runs the normal command. May name the session with ``sessionToken``.
    public var planCommand: String?

    /// How a first prompt is given to a new session, added to the end of the
    /// command line: ``promptToken`` stands for the prompt, quoted for the
    /// shell. `nil` for an agent that cannot be given one, which starts as it
    /// would without.
    public var promptArgument: String?

    /// The command line that picks a session up again after its terminal was
    /// closed, or `nil` for an agent that cannot: it starts afresh instead.
    /// May name the session with ``sessionToken``.
    public var resumeCommand: String?

    /// For an agent that names its own sessions: a command line that lists
    /// them, which Herder reads to learn the id of the one a tab started. See
    /// ``AgentSessionLookup`` for what it may print.
    public var sessionLookup: String?

    /// Variables set for the agent's terminal alone, over the app's own.
    /// For what an agent reads from its environment and nowhere else Herder
    /// can reach, without changing it in the person's other terminals.
    public var environment: [String: String]?

    /// Stands for the session's id in a command. For most agents Herder mints
    /// the id, a UUID, and tells the agent; for one with a ``sessionLookup``,
    /// it is the id the agent chose, once the lookup has found it.
    public static let sessionToken = "{session}"

    /// Stands for the first prompt in ``promptArgument``.
    public static let promptToken = "{prompt}"

    public init(
        id: ID,
        name: String,
        command: String,
        planCommand: String? = nil,
        promptArgument: String? = nil,
        resumeCommand: String? = nil,
        sessionLookup: String? = nil,
        environment: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.planCommand = planCommand
        self.promptArgument = promptArgument
        self.resumeCommand = resumeCommand
        self.sessionLookup = sessionLookup
        self.environment = environment
    }

    /// Whether the agent mints its own session ids, so Herder has to look
    /// them up before it can resume one.
    public var looksUpSessions: Bool {
        !(sessionLookup ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The command line to run for the session called `session`: a new one,
    /// or picking one up. Resuming with no resume command starts afresh.
    /// `mode` only matters for a new session: a resumed one has its mode
    /// already, in the agent's own session.
    ///
    /// `prompt` is the session's first message, for a new session of an agent
    /// that has a ``promptArgument``; a resumed one has had its first message
    /// already, so it is left out.
    public func commandLine(
        session: String,
        resuming: Bool,
        mode: SessionMode = .build,
        prompt: String? = nil
    ) -> String {
        let template = resuming ? (nonBlank(resumeCommand) ?? command) : newCommand(for: mode)
        var line = template.replacing(Self.sessionToken, with: session)
        if !resuming, let argument = promptArgument(for: prompt) { line += " " + argument }
        return line
    }

    private func promptArgument(for prompt: String?) -> String? {
        guard let template = nonBlank(promptArgument), let prompt,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        var quoted = Self.shellQuoted(prompt)
        // A bare prompt that begins with a dash would be read as an option.
        if template == Self.promptToken, prompt.hasPrefix("-") { quoted = "-- " + quoted }
        return template.replacing(Self.promptToken, with: quoted)
    }

    /// `text` as one word for a POSIX shell: in single quotes, with each
    /// single quote closed, escaped and reopened.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacing("'", with: #"'\''"#) + "'"
    }

    private func newCommand(for mode: SessionMode) -> String {
        mode == .plan ? (nonBlank(planCommand) ?? command) : command
    }

    private func nonBlank(_ command: String?) -> String? {
        command.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
    }

    /// The agents Herder knows how to start without being told. Never
    /// change an id: it is what a saved "last used" names.
    ///
    /// Only Claude Code has a plan command: Codex and Pi have no plan flag, and
    /// opencode's `--agent` is not a flag of its terminal UI in the version
    /// this was checked against (2.0.16), so for those plan is the normal command.
    ///
    /// Claude Code and Pi can be given a session's id up front, so they resume
    /// exactly. opencode names its own, so its sessions are looked up and then
    /// resumed exactly. Codex can do neither here: it resumes the last session
    /// in the worktree, which is the right one unless several were open.
    ///
    /// opencode is told to use the `herder` theme, which leaves its background
    /// clear so the pane shows through, as Herder's own terminals do. The
    /// theme is `packages/opencode-theme`; without it opencode falls back to a
    /// theme of its own. What it is doing, and the session's title, reach the
    /// sidebar through `packages/opencode-plugin-osc-7501`; without it the
    /// session reads as idle and is named by opencode's terminal title. The app carries both and links them into opencode's config
    /// folder at launch: see ``OpencodeIntegration``.
    public static let presets: [Agent] = [
        Agent(
            id: "claude-code",
            name: "Claude Code",
            command: "claude --session-id \(sessionToken)",
            planCommand: "claude --session-id \(sessionToken) --permission-mode plan",
            promptArgument: promptToken,
            resumeCommand: "claude --resume \(sessionToken)"
        ),
        Agent(
            id: "codex",
            name: "Codex",
            command: "codex",
            promptArgument: promptToken,
            resumeCommand: "codex resume --last"
        ),
        Agent(
            id: "opencode",
            name: "opencode",
            command: "opencode",
            promptArgument: "--prompt \(promptToken)",
            resumeCommand: "opencode -s \(sessionToken)",
            sessionLookup: "opencode session list --format json -n 20",
            environment: ["OPENCODE_CLI_CONFIG_CONTENT": #"{"theme":{"name":"herder"}}"#]
        ),
        Agent(
            id: "pi",
            name: "Pi",
            command: "pi --session-id \(sessionToken)",
            promptArgument: promptToken,
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
