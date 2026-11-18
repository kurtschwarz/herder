import Core
import Foundation

/// What the popover's search field shows for what has been typed.
enum DiffBaseSearch {
    /// How many commits an empty search lists after the refs.
    static let recentCommitCount = 5

    enum Row: Equatable, Identifiable {
        case ref(GitRef)
        case commit(GitCommit)

        var id: String {
            switch self {
            case .ref(let ref): "ref:\(ref.name)"
            case .commit(let commit): "commit:\(commit.sha)"
            }
        }

        /// What gets stored if the row is picked.
        var base: String {
            switch self {
            case .ref(let ref): ref.name
            case .commit(let commit): commit.sha
            }
        }
    }

    /// Refs whose name holds `query`, newest tip first, as `refs` already is.
    /// Nothing typed lists every ref and then the latest commits.
    static func rows(for query: String, refs: [GitRef], commits: [GitCommit]) -> [Row] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            return refs.map(Row.ref) + commits.prefix(recentCommitCount).map(Row.commit)
        }
        return refs.filter { $0.name.localizedCaseInsensitiveContains(query) }.map(Row.ref)
    }

    /// A SHA or the start of one: git takes four characters.
    static func looksLikeSHA(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespaces)
        return (4...40).contains(text.count) && text.allSatisfy(\.isHexDigit)
    }

    /// What Return picks: the only match, else a pasted SHA that `commit`
    /// confirms, else nothing.
    static func submission(
        for query: String,
        rows: [Row],
        commit: (String) async -> GitCommit?
    ) async -> String? {
        if rows.count == 1 { return rows[0].base }
        let query = query.trimmingCharacters(in: .whitespaces)
        guard looksLikeSHA(query) else { return nil }
        return await commit(query)?.sha
    }
}
