
/// What git says about a working tree, in the shape the tree draws it.
///
/// Built once from one `git status` for the whole repository. Two derivations
/// happen here rather than at render time: the status a path takes from a
/// collapsed folder above it, and the marker a folder carries for what changed
/// inside it. Both need the whole repository at once, which is exactly what the
/// single status call hands over.
public struct WorktreeStatus: Equatable, Sendable {
    public static let empty = WorktreeStatus()

    private var root: PathKey?
    private var entries: [PathKey: GitStatus] = [:]

    /// The untracked and ignored folders every path below them takes its state
    /// from. Few, because `--untracked-files=normal` collapses them.
    private var collapsed: [PathKey: GitStatus] = [:]

    private var rollups: [PathKey: GitMark] = [:]

    public init() {}

    public init(_ worktree: GitWorktreeStatus) {
        let root = worktree.root
        self.root = root
        entries = worktree.entries

        for (path, status) in entries {
            switch status {
            case .untracked, .ignored: collapsed[path] = status
            case .tracked, .unmerged: break
            }
        }

        for (path, status) in entries {
            guard let rollup = GitMark(status) else { continue }
            // Ignored is terminal in both directions: a change buried inside an
            // ignored folder raises no marker, or every repository with a build
            // folder in it would wear one permanently.
            guard !isUnderIgnored(path) else { continue }
            for folder in path.parents(upTo: root) {
                rollups[folder] = max(rollups[folder] ?? rollup, rollup)
            }
        }
    }

    /// What git says about `path`, including what it takes from a collapsed
    /// folder above it. `nil` when git has nothing to say.
    ///
    /// A path git reported for itself wins over anything it would inherit: a
    /// tracked file that is modified inside an ignored folder reads as
    /// modified, which is the one place the two could contend.
    public func status(of path: PathKey) -> GitStatus? {
        if let own = entries[path] { return own }
        return inherited(path)
    }

    /// Whether `path`, or a folder between it and the root, is ignored. Reads
    /// `status(of:)`, so a tracked file inside an ignored folder is not faded
    /// along with it.
    public func isIgnored(_ path: PathKey) -> Bool {
        status(of: path) == .ignored
    }

    /// The marker `folder` carries for what changed inside it, `nil` when there
    /// is nothing to report.
    public func rollup(of folder: PathKey) -> GitMark? {
        rollups[folder]
    }

    private func inherited(_ path: PathKey) -> GitStatus? {
        guard let root, path.isInside(root) else { return nil }
        var current = path
        while let parent = current.parent, parent.path != root.path {
            if let status = collapsed[parent] { return status }
            current = parent
        }
        return nil
    }

    private func isUnderIgnored(_ path: PathKey) -> Bool {
        guard let root, path.isInside(root) else { return false }
        var current = path
        while let parent = current.parent, parent.path != root.path {
            if collapsed[parent] == .ignored { return true }
            current = parent
        }
        return false
    }
}
