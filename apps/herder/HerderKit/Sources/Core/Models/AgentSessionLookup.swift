import Foundation

/// Reading which sessions an agent has, from what its lookup command prints.
///
/// For an agent that mints its own session ids, so Herder cannot name the
/// session up front: once a session exists, the lookup says what it is called,
/// and that is what the resume command is given.
///
/// Two shapes are understood, so that most agents need no glue:
///
/// - A JSON array of objects with an `id`, and optionally the `directory` the
///   session ran in and when it was `created` (seconds or milliseconds since
///   1970). opencode's `session list --format json` is this.
/// - Anything else: one session a line, its id the first word.
public enum AgentSessionLookup {
    public struct Candidate: Equatable, Sendable {
        public var id: String
        public var directory: PathKey?
        public var created: Date?

        public init(id: String, directory: PathKey? = nil, created: Date? = nil) {
            self.id = id
            self.directory = directory
            self.created = created
        }
    }

    public static func candidates(in output: String) -> [Candidate] {
        if let data = output.data(using: .utf8),
           let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        {
            return objects.compactMap { object in
                guard let id = object["id"] as? String, !id.isEmpty else { return nil }
                let directory = (object["directory"] as? String).map { PathKey(URL(filePath: $0)) }
                let created = (object["created"] as? Double).map { value in
                    Date(timeIntervalSince1970: value > 100_000_000_000 ? value / 1000 : value)
                }
                return Candidate(id: id, directory: directory, created: created)
            }
        }
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            line.split(whereSeparator: \.isWhitespace).first.map { Candidate(id: String($0)) }
        }
    }

    /// The session most likely to be the one a tab started at `started` in
    /// `directory`: one that ran there, was made after the tab began, and no
    /// other tab has claimed. The earliest such, since tabs claim theirs in the
    /// order they were opened.
    ///
    /// A little slack before `started`, because the clocks of two programs on
    /// one machine still round differently.
    public static func match(
        _ candidates: [Candidate],
        directory: PathKey,
        started: Date,
        claimed: Set<String>
    ) -> String? {
        let fit = candidates.filter { candidate in
            !claimed.contains(candidate.id)
                && (candidate.directory.map { $0 == directory } ?? true)
                && (candidate.created.map { $0 >= started.addingTimeInterval(-5) } ?? true)
        }
        // With no times to go by, the list's own order is newest first.
        if fit.contains(where: { $0.created != nil }) {
            return fit.min { ($0.created ?? .distantFuture) < ($1.created ?? .distantFuture) }?.id
        }
        return fit.first?.id
    }

    /// Whether `id` can be put in a command line as it is. Anything with a
    /// character a shell would read is refused rather than quoted: an id is
    /// letters, digits and a little punctuation.
    public static func isSafe(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)
        } && id.unicodeScalars.allSatisfy(\.isASCII)
    }
}
