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
}
