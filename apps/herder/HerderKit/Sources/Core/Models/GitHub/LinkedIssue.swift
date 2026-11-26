import Foundation

/// The GitHub issue a session was started from, saved on the session so the
/// sidebar can tell an issue is already being worked on.
///
/// Recorded when the session starts and never looked up again: there is no
/// polling for an issue's state, so nothing here changes.
public struct LinkedIssue: Codable, Sendable, Equatable {
    public var number: Int
    public var title: String
    public var url: URL

    public init(number: Int, title: String, url: URL) {
        self.number = number
        self.title = title
        self.url = url
    }

    /// These keys are on the user's disk, in each session's history file:
    /// renaming one is a migration.
    private enum CodingKeys: String, CodingKey {
        case number, title, url
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = try container.decode(Int.self, forKey: .number)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try container.decode(URL.self, forKey: .url)
    }
}
