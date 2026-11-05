import Foundation
import Models

/// Where a watcher had got to in the file system's event history.
///
/// Opaque: only the watcher knows what the number means. Kept so a stream can
/// be started again from where the last one stopped and replay what happened
/// in between.
public struct FileWatcherPosition: Sendable, Equatable, Hashable {
    public var raw: UInt64

    public init(raw: UInt64) {
        self.raw = raw
    }
}

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

/// Watching the file system for changes.
public protocol FileWatcherClient: Sendable {
    /// Reports changes under `roots` and everything below them until the
    /// stream is dropped or the task awaiting it is cancelled.
    ///
    /// One stream covers several roots because a worktree needs two that have
    /// nothing to do with each other: the working tree, and the git directory
    /// where staging writes — which for a linked worktree is not inside the
    /// working tree at all.
    ///
    /// `from` replays what happened since that position. `nil` starts now.
    func watch(_ roots: [URL], from position: FileWatcherPosition?) -> AsyncStream<FileChangeBatch>
}
