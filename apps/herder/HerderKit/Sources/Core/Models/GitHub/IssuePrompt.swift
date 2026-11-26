import Foundation

/// What an agent is told first when a session starts from an issue: the
/// number and title, the link, the body, then the latest comments.
public enum IssuePrompt {
    /// How many comments go in, the most recent of them.
    public static let maxComments = 50

    public static func text(for detail: GitHubIssueDetail) -> String {
        let issue = detail.issue
        var parts = ["#\(issue.number) \(issue.title)", issue.url.absoluteString]

        let body = detail.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { parts.append(body) }

        let comments = detail.comments.suffix(maxComments).compactMap { comment -> String? in
            let text = comment.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return "\(comment.author.map { "@\($0)" } ?? "ghost"):\n\(text)"
        }
        if !comments.isEmpty {
            parts.append("Comments, oldest first:")
            parts.append(contentsOf: comments)
        }
        return parts.joined(separator: "\n\n")
    }
}
