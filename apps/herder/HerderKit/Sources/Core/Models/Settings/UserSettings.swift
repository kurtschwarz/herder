import Foundation

/// What the user has set, as `settings.json` holds it.
///
/// Resolved, not sparse: every field has its value, the default where the file
/// says nothing. The file is the sparse side. ``encoded(sparse:)`` writes only
/// what differs from the default, and decoding fills in the rest, so a missing
/// key, a missing object and a missing file all mean the default.
///
/// The keys are `snake_case` and nested by the Settings pane they belong to.
/// Once released they are frozen, the same as a `persistenceKey`: they are
/// names on the user's disk, and `settings.schema.json` publishes them. A
/// field is only ever added. Unknown keys are ignored, so a file written for
/// a newer build still reads.
///
/// Secrets are never here: the Anthropic API key and the GitHub tokens stay
/// in the Keychain.
public struct UserSettings: Sendable, Equatable {
    /// Where the schema is published. `$schema` in every file the app writes
    /// points here, so the path in the repository is frozen too.
    public static let schemaURL =
        "https://raw.githubusercontent.com/kurtschwarz/herder/main/apps/herder/settings.schema.json"

    /// `updates.check_automatically`. Pushed into the updater, which is not
    /// the source of truth for it.
    public var checkForUpdatesAutomatically = true

    /// `agents.first_prompt_template`. See ``FirstPromptTemplate``.
    public var firstPromptTemplate = ""

    /// `agents.custom`, in order. Each has a readable, unique id that is not a
    /// preset's: see ``isValidAgentID(_:)``.
    public var customAgents: [Agent] = []

    /// `editor.show_whitespace`.
    public var showWhitespace = ShowWhitespace.none

    /// `providers.anthropic.endpoint`, as typed: it may not be a URL.
    public var anthropicEndpoint = NamingConfiguration.defaultEndpoint

    public init() {}

    // MARK: - Agent ids

    /// Whether `id` may name a custom agent: lowercase letters, digits and
    /// dashes, and not empty.
    public static func isValidAgentID(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    /// A readable id for an agent called `name`, that none of `taken` and no
    /// preset already has: the name in lowercase with dashes between its
    /// words, then `-2`, `-3` and so on.
    public static func mintAgentID(for name: String, taken: some Sequence<Agent.ID>) -> Agent.ID {
        var slug = ""
        for scalar in name.lowercased().unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                slug.unicodeScalars.append(scalar)
            } else if !slug.isEmpty, !slug.hasSuffix("-") {
                slug += "-"
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        if slug.isEmpty { slug = "agent" }

        let used = Set(taken).union(Agent.presets.map(\.id))
        guard used.contains(slug) else { return slug }
        var number = 2
        while used.contains("\(slug)-\(number)") { number += 1 }
        return "\(slug)-\(number)"
    }

    // MARK: - The file

    /// The file's text: pretty-printed, keys in a stable order with
    /// `$schema` first, ending in a newline.
    ///
    /// `sparse` false writes every field, defaults included, which is what the
    /// schema's `default`s are checked against.
    public func encoded(sparse: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        // Sorted, which is stable and puts `$schema` first: `$` sorts before
        // every letter.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.userInfo[Self.writesDefaults] = !sparse
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    /// The settings `text` holds. Throws ``UserSettingsError`` for anything
    /// wrong with it, with a message that says what and where.
    public static func decode(_ text: String) throws -> UserSettings {
        do {
            return try JSONDecoder().decode(UserSettings.self, from: Data(text.utf8))
        } catch let error as UserSettingsError {
            throw error
        } catch let error as DecodingError {
            throw UserSettingsError(error)
        } catch {
            throw UserSettingsError(message: error.localizedDescription)
        }
    }

    static let writesDefaults = CodingUserInfoKey(rawValue: "writesDefaults")!
}

// MARK: - Coding

extension UserSettings: Codable {
    enum RootKeys: String, CodingKey, CaseIterable {
        case schema = "$schema"
        case updates
        case agents
        case editor
        case providers
    }

    enum UpdatesKeys: String, CodingKey, CaseIterable {
        case checkAutomatically = "check_automatically"
    }

    enum AgentsKeys: String, CodingKey, CaseIterable {
        case firstPromptTemplate = "first_prompt_template"
        case custom
    }

    enum EditorKeys: String, CodingKey, CaseIterable {
        case showWhitespace = "show_whitespace"
    }

    enum ProvidersKeys: String, CodingKey, CaseIterable {
        case anthropic
    }

    enum AnthropicKeys: String, CodingKey, CaseIterable {
        case endpoint
    }

    /// An entry of `agents.custom`. Not ``Agent``'s own keys: those are in
    /// snapshots already, camel-cased, and cannot change.
    enum AgentKeys: String, CodingKey, CaseIterable {
        case id
        case type
        case name
        case command
        case planCommand = "plan_command"
        case promptArgument = "prompt_argument"
        case promptNeedsReturn = "prompt_needs_return"
        case resumeCommand = "resume_command"
        case sessionLookup = "session_lookup"
        case environment
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let root = try decoder.container(keyedBy: RootKeys.self)

        if root.contains(.updates) {
            let updates = try root.nestedContainer(keyedBy: UpdatesKeys.self, forKey: .updates)
            checkForUpdatesAutomatically = try updates.decodeIfPresent(Bool.self, forKey: .checkAutomatically)
                ?? checkForUpdatesAutomatically
        }

        if root.contains(.agents) {
            let agents = try root.nestedContainer(keyedBy: AgentsKeys.self, forKey: .agents)
            firstPromptTemplate = try agents.decodeIfPresent(String.self, forKey: .firstPromptTemplate)
                ?? firstPromptTemplate
            if agents.contains(.custom) {
                var list = try agents.nestedUnkeyedContainer(forKey: .custom)
                var seen: Set<Agent.ID> = []
                while !list.isAtEnd {
                    let index = list.currentIndex
                    let entry = try list.nestedContainer(keyedBy: AgentKeys.self)
                    let agent = try Self.decodeAgent(from: entry, at: index)
                    let place = "agents.custom[\(index)].id"
                    guard Self.isValidAgentID(agent.id) else {
                        throw UserSettingsError(message: "\(place) \u{201C}\(agent.id)\u{201D} may only use lowercase letters, digits and dashes.")
                    }
                    guard !agent.isPreset else {
                        throw UserSettingsError(message: "\(place) \u{201C}\(agent.id)\u{201D} is a built-in agent\u{2019}s id.")
                    }
                    guard seen.insert(agent.id).inserted else {
                        throw UserSettingsError(message: "\(place) \u{201C}\(agent.id)\u{201D} is used by another agent.")
                    }
                    customAgents.append(agent)
                }
            }
        }

        if root.contains(.editor) {
            let editor = try root.nestedContainer(keyedBy: EditorKeys.self, forKey: .editor)
            if let value = try editor.decodeIfPresent(String.self, forKey: .showWhitespace) {
                guard let mode = ShowWhitespace(rawValue: value) else {
                    let names = ShowWhitespace.allCases.map(\.rawValue).joined(separator: ", ")
                    throw UserSettingsError(
                        message: "editor.show_whitespace \u{201C}\(value)\u{201D} is not one of \(names)."
                    )
                }
                showWhitespace = mode
            }
        }

        if root.contains(.providers) {
            let providers = try root.nestedContainer(keyedBy: ProvidersKeys.self, forKey: .providers)
            if providers.contains(.anthropic) {
                let anthropic = try providers.nestedContainer(keyedBy: AnthropicKeys.self, forKey: .anthropic)
                anthropicEndpoint = try anthropic.decodeIfPresent(String.self, forKey: .endpoint) ?? anthropicEndpoint
            }
        }
    }

    /// An entry with a `type` starts from that preset: what the entry leaves
    /// out is the preset's, and its environment is laid over the preset's.
    private static func decodeAgent(from entry: KeyedDecodingContainer<AgentKeys>, at index: Int) throws -> Agent {
        let type = try entry.decodeIfPresent(String.self, forKey: .type)
        let base: Agent?
        if let type {
            guard let preset = Agent.preset(type) else {
                let names = Agent.presets.map(\.id).joined(separator: ", ")
                throw UserSettingsError(
                    message: "agents.custom[\(index)].type \u{201C}\(type)\u{201D} is not a built-in agent: one of \(names)."
                )
            }
            base = preset
        } else {
            base = nil
        }
        let environment = try entry.decodeIfPresent([String: String].self, forKey: .environment)
        let merged = (base?.environment ?? [:]).merging(environment ?? [:]) { $1 }
        return Agent(
            id: try entry.decode(String.self, forKey: .id),
            name: try entry.decodeIfPresent(String.self, forKey: .name) ?? base?.name ?? "",
            command: try entry.decodeIfPresent(String.self, forKey: .command) ?? base?.command ?? "",
            planCommand: try entry.decodeIfPresent(String.self, forKey: .planCommand) ?? base?.planCommand,
            promptArgument: try entry.decodeIfPresent(String.self, forKey: .promptArgument) ?? base?.promptArgument,
            promptNeedsReturn: try entry.decodeIfPresent(Bool.self, forKey: .promptNeedsReturn) ?? base?.promptNeedsReturn,
            resumeCommand: try entry.decodeIfPresent(String.self, forKey: .resumeCommand) ?? base?.resumeCommand,
            sessionLookup: try entry.decodeIfPresent(String.self, forKey: .sessionLookup) ?? base?.sessionLookup,
            environment: merged.isEmpty ? nil : merged,
            type: type
        )
    }

    /// Writes `agent` as an entry: every field it has, or, for one with a
    /// `type`, only those that differ from the preset. A field the preset
    /// has and the agent does not is written empty, which is how the file
    /// says none.
    private static func encodeAgent(_ agent: Agent, into entry: inout KeyedEncodingContainer<AgentKeys>) throws {
        try entry.encode(agent.id, forKey: .id)
        guard let type = agent.type, let base = Agent.preset(type) else {
            try entry.encode(agent.name, forKey: .name)
            try entry.encode(agent.command, forKey: .command)
            try entry.encodeIfPresent(agent.planCommand, forKey: .planCommand)
            try entry.encodeIfPresent(agent.promptArgument, forKey: .promptArgument)
            try entry.encodeIfPresent(agent.promptNeedsReturn, forKey: .promptNeedsReturn)
            try entry.encodeIfPresent(agent.resumeCommand, forKey: .resumeCommand)
            try entry.encodeIfPresent(agent.sessionLookup, forKey: .sessionLookup)
            try entry.encodeIfPresent(agent.environment, forKey: .environment)
            return
        }
        try entry.encode(type, forKey: .type)
        if agent.name != base.name { try entry.encode(agent.name, forKey: .name) }
        if agent.command != base.command { try entry.encode(agent.command, forKey: .command) }
        func differing(_ value: String?, _ preset: String?, _ key: AgentKeys) throws {
            if value != preset { try entry.encode(value ?? "", forKey: key) }
        }
        try differing(agent.planCommand, base.planCommand, .planCommand)
        try differing(agent.promptArgument, base.promptArgument, .promptArgument)
        if (agent.promptNeedsReturn ?? false) != (base.promptNeedsReturn ?? false) {
            try entry.encode(agent.promptNeedsReturn ?? false, forKey: .promptNeedsReturn)
        }
        try differing(agent.resumeCommand, base.resumeCommand, .resumeCommand)
        try differing(agent.sessionLookup, base.sessionLookup, .sessionLookup)
        let own = (agent.environment ?? [:]).filter { base.environment?[$0.key] != $0.value }
        if !own.isEmpty { try entry.encode(own, forKey: .environment) }
    }

    public func encode(to encoder: any Encoder) throws {
        let all = encoder.userInfo[Self.writesDefaults] as? Bool ?? false
        let defaults = UserSettings()
        var root = encoder.container(keyedBy: RootKeys.self)
        try root.encode(Self.schemaURL, forKey: .schema)

        if all || checkForUpdatesAutomatically != defaults.checkForUpdatesAutomatically {
            var updates = root.nestedContainer(keyedBy: UpdatesKeys.self, forKey: .updates)
            try updates.encode(checkForUpdatesAutomatically, forKey: .checkAutomatically)
        }

        let writesTemplate = all || firstPromptTemplate != defaults.firstPromptTemplate
        let writesCustom = all || !customAgents.isEmpty
        if writesTemplate || writesCustom {
            var agents = root.nestedContainer(keyedBy: AgentsKeys.self, forKey: .agents)
            if writesTemplate { try agents.encode(firstPromptTemplate, forKey: .firstPromptTemplate) }
            if writesCustom {
                var list = agents.nestedUnkeyedContainer(forKey: .custom)
                for agent in customAgents {
                    var entry = list.nestedContainer(keyedBy: AgentKeys.self)
                    try Self.encodeAgent(agent, into: &entry)
                }
            }
        }

        if all || showWhitespace != defaults.showWhitespace {
            var editor = root.nestedContainer(keyedBy: EditorKeys.self, forKey: .editor)
            try editor.encode(showWhitespace.rawValue, forKey: .showWhitespace)
        }

        if all || anthropicEndpoint != defaults.anthropicEndpoint {
            var providers = root.nestedContainer(keyedBy: ProvidersKeys.self, forKey: .providers)
            var anthropic = providers.nestedContainer(keyedBy: AnthropicKeys.self, forKey: .anthropic)
            try anthropic.encode(anthropicEndpoint, forKey: .endpoint)
        }
    }
}
