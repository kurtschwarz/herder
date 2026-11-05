/// A batch of changes the watcher noticed.
///
/// Batched rather than one event at a time because that is how the file system
/// reports them: a burst of writes arrives as one list, already coalesced,
/// before any of this code runs.
public struct FileChangeBatch: Sendable, Equatable {
    /// The folders whose contents may have changed.
    ///
    /// Folders, not files: that is the granularity the file system reports by
    /// default, and it maps exactly onto "read this folder again", which is the
    /// only thing a tree can do in response.
    public var folders: Set<PathKey>

    /// Roots that were moved or deleted from under the watcher. The app's whole
    /// job is managing worktrees, so a worktree being removed in a terminal is
    /// an ordinary Tuesday rather than an edge case.
    public var vanishedRoots: Set<PathKey>

    /// The watcher's event queue overflowed and events were dropped, so
    /// `folders` cannot be trusted to be the whole story and everything has to
    /// be read again. The system admitting this is better than guessing at it.
    public var needsFullScan: Bool

    public var position: FileWatcherPosition

    public init(
        folders: Set<PathKey> = [],
        vanishedRoots: Set<PathKey> = [],
        needsFullScan: Bool = false,
        position: FileWatcherPosition = FileWatcherPosition(raw: 0)
    ) {
        self.folders = folders
        self.vanishedRoots = vanishedRoots
        self.needsFullScan = needsFullScan
        self.position = position
    }
}
