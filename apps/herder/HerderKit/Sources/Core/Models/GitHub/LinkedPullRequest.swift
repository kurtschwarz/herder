import Foundation

/// The pull request GitHub has for a session's branch: what a badge shows, and
/// enough to open it. Saved on the session, so it can be looked up later and
/// survives a relaunch.
///
/// One per session, the most recent: a reopened pull request updates it in
/// place, and a newer one replaces it.
public struct LinkedPullRequest: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case open
        case merged
        case closed
        /// A state this build does not know.
        case unknown

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Self(rawValue: raw) ?? .unknown
        }

        /// Whether it is still worth asking GitHub about: nothing more is
        /// expected of a merged or closed one.
        public var isSettled: Bool { self == .merged || self == .closed }
    }

    public var number: Int
    public var url: URL
    public var title: String
    public var state: State
    public var isDraft: Bool
    public var mergedAt: Date?
    public var updatedAt: Date

    public init(
        number: Int,
        url: URL,
        title: String,
        state: State,
        isDraft: Bool = false,
        mergedAt: Date? = nil,
        updatedAt: Date
    ) {
        self.number = number
        self.url = url
        self.title = title
        self.state = state
        self.isDraft = isDraft
        self.mergedAt = mergedAt
        self.updatedAt = updatedAt
    }

    /// These keys are on the user's disk, in each session's history file:
    /// renaming one is a migration.
    private enum CodingKeys: String, CodingKey {
        case number, url, title, state, isDraft, mergedAt, updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = try container.decode(Int.self, forKey: .number)
        url = try container.decode(URL.self, forKey: .url)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        state = try container.decodeIfPresent(State.self, forKey: .state) ?? .unknown
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
        mergedAt = try container.decodeIfPresent(Date.self, forKey: .mergedAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}
