import Foundation

/// One agent session: an agent's terminal UI in a worktree, from the moment
/// its tab opens, through the run, to the day the history lists it as ended.
///
/// Two parts with two lifetimes, kept in two places. The record — what it is,
/// where it ran, when it started and ended — is app-wide, in
/// ``AgentSessions``, which writes it to disk once the agent has first run.
/// ``live`` is what a window's panel says about it while its tab is open:
/// what it is doing, and when it last wrote anything. That is the window's,
/// in its ``WindowAgentSessions``: it changes every second, which must redraw
/// that window's sidebar and no other, and it is never written down.
///
/// Metadata only. What was said in the session stays with the agent that kept
/// it. Everything the sidebar needs to draw it is copied in, because the
/// things it came from do not last: a worktree is removed with `git` in a
/// terminal, a branch is renamed, and a custom agent is deleted in Settings.
///
/// Herder does not talk to agents. What it knows of a running one is what any
/// terminal knows: the title the program gave itself, the status it reports
/// (OSC 7501), and whether it has exited.
public struct AgentSession: Codable, Sendable, Equatable, Identifiable {
    /// What a session with an open tab seems to be doing.
    public enum State: Sendable, Equatable {
        /// Remembered from before, and not yet picked up again: it resumes
        /// when its tab is shown.
        case paused
        case starting
        /// Reported working.
        case working
        /// Reported blocked on the person, with what it said.
        case needsInput(String?)
        /// Reported nothing that needs anyone, or nothing at all.
        case idle
        /// The terminal UI exited with this status.
        case exited(Int32)
        /// It could not be started.
        case failed

        /// Whether the agent is running, so it can be said to have been seen.
        public var isRunning: Bool {
            switch self {
            case .working, .needsInput, .idle: true
            case .paused, .starting, .exited, .failed: false
            }
        }
    }

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

    /// The session's tab, open in a window, and what it shows. Which window
    /// is not here: it is whichever ``WindowAgentSessions`` holds it.
    public struct Live: Sendable, Equatable {
        public var state: State

        /// When it was opened, last worked, or last changed what it says it
        /// is doing. For a program that says nothing, when it last wrote
        /// anything.
        public var lastActivity: Date

        public init(state: State, lastActivity: Date) {
            self.state = state
            self.lastActivity = lastActivity
        }
    }

    /// The tab's id, which survives resuming: a resumed session is this one
    /// again, not a new one.
    public var id: UUID

    /// Which agent runs it, and what it was called then. See ``Agent/id``.
    public var agentID: Agent.ID
    public var agentName: String

    /// The agent's own id for the session, which is what resuming it needs.
    /// `nil` for an agent that gives none, and until a lookup finds it for one
    /// that names its own.
    public var sessionID: String?

    /// The worktree it runs in, and what that had checked out when it
    /// started: a branch name, or a short commit when `HEAD` was detached.
    public var worktree: WorkspaceID
    public var branch: String?

    /// What it is called: the person's name for it, else the program's, else
    /// the agent's.
    public var title: String

    /// The name the person gave it, if any: what its tab is called again
    /// when it is resumed, where the program's title would not last.
    public var name: String?

    public var startedAt: Date

    /// The last time anything here saw it running. What ``endedAt`` becomes
    /// for a session that was not seen to end.
    public var lastSeenAt: Date

    /// `nil` while it is open.
    public var endedAt: Date?
    public var endReason: EndReason?

    /// The most recent pull request GitHub has for ``branch`` in its repository,
    /// once one has been found. Found by branch, so it is the same for every
    /// session of that branch.
    public var pullRequest: LinkedPullRequest?

    /// The GitHub issue it was started from, if it was.
    public var issue: LinkedIssue?

    /// `nil` in the app-wide record, and set on the copy a window lists while
    /// it has the tab open.
    public var live: Live?

    public var isEnded: Bool { endedAt != nil }

    /// What its tab is doing, if it has one open.
    public var state: State? { live?.state }

    public init(
        id: UUID,
        agentID: Agent.ID,
        agentName: String,
        sessionID: String? = nil,
        worktree: WorkspaceID,
        branch: String? = nil,
        title: String,
        name: String? = nil,
        startedAt: Date,
        lastSeenAt: Date? = nil,
        endedAt: Date? = nil,
        endReason: EndReason? = nil,
        pullRequest: LinkedPullRequest? = nil,
        issue: LinkedIssue? = nil,
        live: Live? = nil
    ) {
        self.id = id
        self.agentID = agentID
        self.agentName = agentName
        self.sessionID = sessionID
        self.worktree = worktree
        self.branch = branch
        self.title = title
        self.name = name
        self.startedAt = startedAt
        self.lastSeenAt = lastSeenAt ?? startedAt
        self.endedAt = endedAt
        self.endReason = endReason
        self.pullRequest = pullRequest
        self.issue = issue
        self.live = live
    }

    /// The record alone, as it goes to disk. These keys are on the user's
    /// disk, under `history/`: renaming one is a migration. ``live`` is not
    /// among them.
    private enum CodingKeys: String, CodingKey {
        case id, agentID, agentName, sessionID, worktree, branch, title, name
        case startedAt, lastSeenAt, endedAt, endReason, pullRequest, issue
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
        name = try container.decodeIfPresent(String.self, forKey: .name)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt) ?? startedAt
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        endReason = try container.decodeIfPresent(EndReason.self, forKey: .endReason)
        if endedAt != nil, endReason == nil { endReason = .unknown }
        pullRequest = try container.decodeIfPresent(LinkedPullRequest.self, forKey: .pullRequest)
        issue = try container.decodeIfPresent(LinkedIssue.self, forKey: .issue)
        live = nil
    }

    /// The record without the live part: what is compared to decide whether
    /// there is anything new to write down.
    public var record: AgentSession {
        var record = self
        record.live = nil
        return record
    }
}

extension AgentSession.EndReason {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }
}
