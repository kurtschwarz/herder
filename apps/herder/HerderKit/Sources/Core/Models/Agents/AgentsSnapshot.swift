import Foundation

/// The agents the user added, and which one they used last, as they go to
/// ``StateStore``.
///
/// The presets are not here: they are code, so a new one reaches everybody
/// and a changed command does not stay stale on somebody's disk.
///
/// Only ``lastUsed`` is read now. ``custom`` and ``firstPromptTemplate`` are
/// user settings, in `settings.json`; they were moved there once, by
/// ``UserSettingsStore``, and are kept as they were and never written again.
public struct AgentsSnapshot: Codable, Sendable, Equatable {
    /// Where this snapshot is stored. A file name on the user's disk, so never
    /// renamed without a migration.
    public static let persistenceKey = "agents"

    public var version = 1
    public var custom: [Agent]
    public var lastUsed: Agent.ID?
    public var firstPromptTemplate: String?

    public init(custom: [Agent] = [], lastUsed: Agent.ID? = nil, firstPromptTemplate: String? = nil) {
        self.custom = custom
        self.lastUsed = lastUsed
        self.firstPromptTemplate = firstPromptTemplate
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        custom = try container.decodeIfPresent([Agent].self, forKey: .custom) ?? []
        lastUsed = try container.decodeIfPresent(Agent.ID.self, forKey: .lastUsed)
        firstPromptTemplate = try container.decodeIfPresent(String.self, forKey: .firstPromptTemplate)
    }
}
