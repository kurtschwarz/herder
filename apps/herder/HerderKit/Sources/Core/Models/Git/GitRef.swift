import Foundation

/// A branch or tag a diff base can name, with when its tip was committed.
public struct GitRef: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case branch
        case remoteBranch
        case tag
    }

    /// The short name: `main`, `origin/main`, `v1.2`.
    public var name: String
    public var kind: Kind
    public var date: Date

    public init(name: String, kind: Kind, date: Date) {
        self.name = name
        self.kind = kind
        self.date = date
    }

    /// Reads `git for-each-ref --format=%(refname)%00%(committerdate:unix)`,
    /// one ref per line. Newest first, and a remote's own `HEAD` pointer left
    /// out: it names a branch that is listed already.
    public static func parse(_ output: String) -> [GitRef] {
        var refs: [GitRef] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\0", omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let full = String(parts[0])
            let date = Date(timeIntervalSince1970: TimeInterval(parts[1]) ?? 0)

            if full.hasPrefix("refs/heads/") {
                refs.append(GitRef(name: String(full.dropFirst("refs/heads/".count)), kind: .branch, date: date))
            } else if full.hasPrefix("refs/remotes/") {
                let name = String(full.dropFirst("refs/remotes/".count))
                guard !name.hasSuffix("/HEAD") else { continue }
                refs.append(GitRef(name: name, kind: .remoteBranch, date: date))
            } else if full.hasPrefix("refs/tags/") {
                refs.append(GitRef(name: String(full.dropFirst("refs/tags/".count)), kind: .tag, date: date))
            }
        }
        return refs.sorted { $0.date > $1.date }
    }
}
