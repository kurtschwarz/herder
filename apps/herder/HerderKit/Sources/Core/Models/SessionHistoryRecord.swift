import Foundation

/// One agent session, from the first time its terminal UI started until it
/// ended, as the sidebar's history lists it.
///
/// Metadata only. What was said in the session stays with the agent that kept
/// it: this is enough to say what it was, where and when, and to resume it.
///
/// Everything the sidebar needs to draw it is copied in, because the things it
/// came from do not last: a worktree is removed with `git` in a terminal, a
/// branch is renamed, and a custom agent is deleted in Settings.
public struct SessionHistoryRecord: Codable, Sendable, Equatable, Identifiable {
    /// Why a session is over. A new reason is a new case, and one this build
    /// does not know reads as ``unknown``.
    public enum EndReason: String, Codable, Sendable {
        /// The person closed its tab.
        case closed
        /// The terminal UI quit by itself, with status 0.
        case exited
        /// Nothing says: Herder stopped without seeing it end.
        case unknown
    }

    /// The tab's id, which survives resuming: a resumed session is this
    /// record again, not a new one.
    public var id: UUID

    /// Which agent ran it, and what it was called then. See ``Agent/id``.
    public var agentID: Agent.ID
    public var agentName: String

    /// The agent's own id for the session, which is what resuming it needs.
    /// `nil` for an agent that gives none, and until a lookup finds it for one
    /// that names its own.
    public var sessionID: String?

    /// The worktree it ran in, and what it had checked out when it started:
    /// a branch name, or a short commit when `HEAD` was detached.
    public var worktree: WorkspaceID
    public var branch: String?

    /// What it was last called: the person's name for it, else the program's.
    public var title: String

    public var startedAt: Date

    /// The last time anything here saw it running. What ``endedAt`` becomes
    /// for a session that was not seen to end.
    public var lastSeenAt: Date

    /// `nil` while it is open.
    public var endedAt: Date?
    public var endReason: EndReason?

    public var isEnded: Bool { endedAt != nil }

    public init(
        id: UUID,
        agentID: Agent.ID,
        agentName: String,
        sessionID: String? = nil,
        worktree: WorkspaceID,
        branch: String? = nil,
        title: String,
        startedAt: Date,
        lastSeenAt: Date? = nil,
        endedAt: Date? = nil,
        endReason: EndReason? = nil
    ) {
        self.id = id
        self.agentID = agentID
        self.agentName = agentName
        self.sessionID = sessionID
        self.worktree = worktree
        self.branch = branch
        self.title = title
        self.startedAt = startedAt
        self.lastSeenAt = lastSeenAt ?? startedAt
        self.endedAt = endedAt
        self.endReason = endReason
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        agentID = try container.decode(Agent.ID.self, forKey: .agentID)
        agentName = try container.decodeIfPresent(String.self, forKey: .agentName) ?? agentID
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        worktree = try container.decode(WorkspaceID.self, forKey: .worktree)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? agentName
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt) ?? startedAt
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        endReason = (try? container.decodeIfPresent(EndReason.self, forKey: .endReason)) ?? nil
        if endedAt != nil, endReason == nil { endReason = .unknown }
    }
}

extension SessionHistoryRecord.EndReason {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }
}
