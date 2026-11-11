/// Which branch a repository's work is measured against.
public enum GitDefaultBranch {
    /// `originHead` (what `origin/HEAD` points at, such as `origin/main`) if it
    /// is set and exists, else `main`, else `master`. `nil` when none of them
    /// exists. `exists` is asked once per candidate, in that order, and only as
    /// far as an answer is needed.
    public static func resolve(originHead: String?, exists: (String) -> Bool) -> String? {
        let candidates = (originHead.map { [$0] } ?? []) + ["main", "master"]
        return candidates.first { !$0.isEmpty && exists($0) }
    }
}
