import Foundation

/// An issue named by what a person pasted: `#123`, or the link to it.
public struct IssueReference: Sendable, Equatable {
    public var number: Int
    /// `owner/name`, for a link; `nil` for a bare number, which means the
    /// repository being listed.
    public var repository: String?

    public init(number: Int, repository: String? = nil) {
        self.number = number
        self.repository = repository
    }

    /// `nil` for text that names no issue, such as a search for a word.
    public init?(parsing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("#"), let number = Int(trimmed.dropFirst()), number > 0 {
            self.init(number: number)
            return
        }

        guard let url = URL(string: trimmed), let host = url.host(), url.scheme == "https" || url.scheme == "http",
              host.caseInsensitiveCompare("github.com") == .orderedSame
        else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 4, parts[2] == "issues", let number = Int(parts[3]), number > 0 else { return nil }
        self.init(number: number, repository: "\(parts[0])/\(parts[1])")
    }
}
