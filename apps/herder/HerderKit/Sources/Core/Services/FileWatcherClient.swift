import Foundation

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
