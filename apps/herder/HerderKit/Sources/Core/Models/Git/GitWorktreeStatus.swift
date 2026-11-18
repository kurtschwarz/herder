/// What one `git status` says about a whole working tree.
public struct GitWorktreeStatus: Sendable, Equatable {
    /// The working tree the entries lie under.
    public var root: PathKey

    /// Every path git reported. An untracked or ignored *folder* appears as the
    /// folder and nothing below it, because `--untracked-files=normal`
    /// collapses them: a fresh `node_modules` is one entry rather than three
    /// hundred thousand, and everything inside takes its state from the folder.
    ///
    /// Holds more paths than the tree draws. A deleted file is still here, and
    /// so is the path a rename came from, because that is the only thing that
    /// can tell a folder something went missing inside it.
    public var entries: [PathKey: GitStatus]

    public init(root: PathKey, entries: [PathKey: GitStatus] = [:]) {
        self.root = root
        self.entries = entries
    }

    /// The same tree with its tracked paths read against a diff base instead
    /// of `HEAD` and the index: `files` are what differs from the base, so a
    /// file changed and changed back is no longer here, and one the base
    /// lacks is added. Untracked, ignored and conflicted entries are kept as
    /// they were.
    ///
    /// A rename also leaves its old path as deleted, as `git status` does, so
    /// the folder it left can say something went missing.
    public func comparing(with files: [GitChangedFile]) -> GitWorktreeStatus {
        var result = entries.filter { _, status in
            if case .tracked = status { return false }
            return true
        }
        for file in files {
            let path = root.appending(file.path)
            if case .unmerged? = entries[path] { continue }
            switch file.status {
            case .modified: result[path] = .tracked(staged: .unchanged, unstaged: .modified)
            case .added: result[path] = .tracked(staged: .unchanged, unstaged: .added)
            case .deleted: result[path] = .tracked(staged: .unchanged, unstaged: .deleted)
            case .renamed:
                result[path] = .tracked(staged: .unchanged, unstaged: .renamed)
                if let previous = file.previousPath {
                    result[root.appending(previous)] = .tracked(staged: .unchanged, unstaged: .deleted)
                }
            }
        }
        return GitWorktreeStatus(root: root, entries: result)
    }
}
