/// The revision the editor compares the working copy with, and what became of
/// it the last time it was looked up.
///
/// ``ref`` is what the user picked and is what is remembered: a symbolic name
/// such as `HEAD~1` or `@{upstream}` keeps following the repository, where a
/// SHA would go stale at the next commit.
public struct GitDiffBase: Equatable, Sendable {
    public static let head = "HEAD"
    public static let upstream = "@{upstream}"
    public static let previousCommit = "HEAD~1"

    /// What is stored: `HEAD`, `HEAD~1`, `@{upstream}`, a ref name or a SHA.
    public var ref: String

    /// What the trigger calls it: `HEAD`, or the ref with `@{upstream}`
    /// replaced by the branch it stands for.
    public var name: String

    /// What the working copy is compared with: the merge-base of `HEAD` and the
    /// ref, or `HEAD` itself when the ref did not resolve.
    public var revision: String

    /// False when ``ref`` is stored but names nothing, so ``revision`` is the
    /// `HEAD` it fell back to.
    public var isResolved: Bool

    public init(ref: String, name: String, revision: String, isResolved: Bool) {
        self.ref = ref
        self.name = name
        self.revision = revision
        self.isResolved = isResolved
    }

    /// The default: edits since the last commit.
    public static let uncommitted = GitDiffBase(ref: head, name: head, revision: head, isResolved: true)

    public var isUncommitted: Bool { ref == Self.head }
}
