import Foundation
import Observation

/// The worktrees the app is holding state for.
///
/// A collection with one member in it. Written as a registry rather than as a
/// single value because the thing it grows into — watching every open worktree
/// so the sidebar can say which have uncommitted work — is then a matter of
/// adding entries instead of turning the design inside out. Each entry costs a
/// watcher and a status call, so widening it is a deliberate step and not a
/// side effect of switching worktrees.
@MainActor
@Observable
public final class WorkspaceRegistry {
    private let files: any FileClient
    private let git: any GitClient
    private let watcher: any FileWatcherClient
    private let clock: any ClockClient

    private var states: [PathKey: Workspace] = [:]

    /// Where each worktree's watcher had got to, kept after its state is
    /// dropped. Coming back to a worktree then replays what changed while
    /// nobody was watching it, instead of starting blind.
    private var positions: [PathKey: FileWatcherPosition] = [:]

    public init(
        files: any FileClient,
        git: any GitClient,
        watcher: any FileWatcherClient,
        clock: any ClockClient
    ) {
        self.files = files
        self.git = git
        self.watcher = watcher
        self.clock = clock
    }

    public func state(for worktree: URL) -> Workspace? {
        states[PathKey(worktree)]
    }

    /// The state of whichever held worktree `path` lies inside.
    public func state(containing path: PathKey) -> Workspace? {
        states.values.first { path.isInside($0.root) }
    }

    /// Holds state for `worktree` and nothing else, stopping whatever else was
    /// being watched.
    ///
    /// Keeps what is already there for the same worktree, so coming back to one
    /// is instant and does not re-read folders that have not changed.
    ///
    /// Returns before anything has been read. The caller is expected to hold
    /// the state and then refresh it, so the folders show as they are read
    /// rather than all at once after git has also answered.
    @discardableResult
    public func select(_ worktree: URL?) async -> Workspace? {
        // Canonicalised here, at the edge of the module, so the listings, the
        // status map and the watcher's own event paths are all the one spelling
        // and compare by construction rather than by luck.
        let key = worktree.map(PathKey.init)

        for (path, state) in states where path != key {
            if let position = state.position { positions[path] = position }
            state.stop()
            states[path] = nil
        }
        guard let key else { return nil }
        if let existing = states[key], existing.isAvailable { return existing }

        // A folder that is not a working tree has no index to watch, which is
        // not a failure: the working tree alone is still worth watching.
        let gitDirectory = try? await git.gitDirectory(of: key.url).map(PathKey.init)
        let state = Workspace(
            root: key,
            gitDirectory: gitDirectory ?? nil,
            from: positions[key],
            files: files,
            git: git,
            watcher: watcher,
            clock: clock
        )
        states[key] = state
        state.beginWatching()
        return state
    }

    /// Whether drains may run. Suspended when the window is not in front:
    /// changes keep accumulating, and are acted on in one go when it comes
    /// back.
    public func setDraining(_ enabled: Bool) {
        for state in states.values { state.setDraining(enabled) }
    }

    public func stop() {
        for (path, state) in states {
            if let position = state.position { positions[path] = position }
            state.stop()
        }
        states = [:]
    }
}
