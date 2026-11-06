import Foundation
import Observation

/// The worktrees the app is holding state for.
///
/// Every worktree that has been opened stays open until it is closed or the app
/// quits. Switching between them changes which window shows which and nothing
/// else: the folders a worktree had read stay read, its git state stays current,
/// and — when there are any — its terminals and agent sessions keep running.
/// That is the point of the whole hierarchy, and it is what switching used to
/// break by tearing down everything but the worktree being shown.
///
/// ## What a background workspace costs
///
/// A watcher, and nothing else. **A workspace drains only while a frontmost
/// window is showing it**: events accumulate in the ones that are not, and are
/// acted on in one go when they come forward. Draining is what costs a
/// subprocess — a drain asks git once for the whole repository — so the ceiling
/// is about one `git status` a second for the workspace on screen, however many
/// are held.
///
/// There is deliberately no cap on how many are held. A cap would mean closing
/// one the user had not asked to close, which is the thing this class exists to
/// stop; if that becomes a problem it wants a visible "close worktree" rather
/// than an eviction they cannot see.
@MainActor
@Observable
public final class WorkspaceRegistry {
    private let files: any FileClient
    private let git: any GitClient
    private let watcher: any FileWatcherClient
    private let clock: any ClockClient
    private let state: any StateStore

    private var states: [PathKey: Workspace] = [:]

    /// Where each worktree's watcher had got to, kept after its state is
    /// dropped. Coming back to a worktree then replays what changed while
    /// nobody was watching it, instead of starting blind.
    private var positions: [PathKey: FileWatcherPosition] = [:]

    /// Which workspace each window is showing, keyed by the window's identity.
    ///
    /// Keyed rather than counted: a window says what it is showing and says it
    /// again when that changes, so there is no begin/end pair to get wrong and
    /// no count to drift. Several windows may name the same workspace.
    private var displayed: [ObjectIdentifier: WorkspaceID] = [:]

    /// Who is keeping each workspace open. A workspace is held while any window
    /// names it in its open set, and let go when the last of them lets go.
    ///
    /// Distinct from ``displayed``: showing a workspace and holding one are
    /// different things. Switching away from a worktree must not tear it down,
    /// so only holding decides how long it lives.
    private var holders: [PathKey: Set<ObjectIdentifier>] = [:]

    /// Whether any of the app's windows is in front. Drains are suspended when
    /// none is: the worst event storms happen while the user is in a terminal
    /// watching the build that is causing them.
    private var isFrontmost = true

    public init(
        files: any FileClient,
        git: any GitClient,
        watcher: any FileWatcherClient,
        clock: any ClockClient,
        state: any StateStore
    ) {
        self.files = files
        self.git = git
        self.watcher = watcher
        self.clock = clock
        self.state = state
    }

    /// Every workspace being held, in no particular order.
    public var workspaces: [Workspace] { Array(states.values) }

    /// The workspace `id` names, if it is open.
    public func workspace(for id: WorkspaceID) -> Workspace? {
        states[id.root]
    }

    public func state(for worktree: URL) -> Workspace? {
        states[PathKey(worktree)]
    }

    /// The state of whichever held worktree `path` lies inside.
    public func state(containing path: PathKey) -> Workspace? {
        states.values.first { path.isInside($0.root) }
    }

    // MARK: - Opening and closing

    /// Opens the worktree `id` names, or hands back the one already open for it.
    ///
    /// Opening an already-open workspace is free and changes nothing, so a
    /// window switching back to one finds it exactly as it left it.
    ///
    /// Returns before anything has been read. The caller is expected to hold
    /// the workspace and then refresh it, so the folders show as they are read
    /// rather than all at once after git has also answered.
    ///
    /// `holder` is whoever wants it kept: a window, for the workspaces in its
    /// open set. Without one the workspace is held by nobody in particular and
    /// lasts until ``close(_:holder:)`` is asked to drop it outright.
    @discardableResult
    public func open(_ id: WorkspaceID, holder: AnyObject? = nil) async -> Workspace? {
        let key = id.root
        if let holder { holders[key, default: []].insert(ObjectIdentifier(holder)) }
        if let existing = states[key], existing.isAvailable { return existing }

        // A folder that is not a working tree has no index to watch, which is
        // not a failure: the working tree alone is still worth watching.
        let gitDirectory = try? await git.gitDirectory(of: key.url).map(PathKey.init)
        let workspace = Workspace(
            root: key,
            gitDirectory: gitDirectory ?? nil,
            from: positions[key],
            files: files,
            git: git,
            watcher: watcher,
            clock: clock,
            state: state
        )
        states[key] = workspace
        // Before the caller gets it, so a feature asking for its UI state finds
        // the last run's already in it.
        await workspace.restoreSnapshot()
        workspace.beginWatching()
        updateDraining()
        return workspace
    }

    /// Lets go of a workspace: writes what it was showing, stops watching, and
    /// drops it.
    ///
    /// With a `holder`, only that holder lets go, and the workspace goes with it
    /// only if nobody else is holding it: a second window on the same checkout
    /// keeps it open. Without one it is dropped whoever holds it.
    ///
    /// Keeps where its watcher had got to, so opening it again replays what
    /// changed in between rather than starting blind.
    public func close(_ id: WorkspaceID, holder: AnyObject? = nil) async {
        let key = id.root
        if let holder {
            holders[key]?.remove(ObjectIdentifier(holder))
            guard holders[key]?.isEmpty ?? true else { return }
        }
        holders[key] = nil
        guard let workspace = states[key] else { return }
        if let position = workspace.position { positions[key] = position }
        // Before stopping it, which cancels any save still waiting out its
        // debounce.
        await workspace.saveSnapshot()
        workspace.stop()
        states[key] = nil
        updateDraining()
    }

    /// Lets go of everything `holder` was holding that nobody else is. For a
    /// window closing.
    public func release(holder: AnyObject) async {
        let mine = ObjectIdentifier(holder)
        for key in holders.filter({ $0.value.contains(mine) }).keys {
            await close(WorkspaceID(key), holder: holder)
        }
    }

    // MARK: - Draining

    /// Says which workspace `window` is showing, or `nil` for none.
    ///
    /// Idempotent: a window may say the same thing twice. Call it whenever what
    /// the window shows changes, and ``stopDisplaying(from:)`` when it closes.
    public func display(_ id: WorkspaceID?, from window: AnyObject) {
        displayed[ObjectIdentifier(window)] = id
        updateDraining()
    }

    public func stopDisplaying(from window: AnyObject) {
        displayed[ObjectIdentifier(window)] = nil
        updateDraining()
    }

    /// Whether any window is in front. See ``isFrontmost``.
    public func setFrontmost(_ frontmost: Bool) {
        guard frontmost != isFrontmost else { return }
        isFrontmost = frontmost
        updateDraining()
    }

    private func updateDraining() {
        let onScreen = Set(displayed.values.map(\.root))
        for (path, workspace) in states {
            workspace.setDraining(isFrontmost && onScreen.contains(path))
        }
    }

    // MARK: - Stopping

    /// Puts every workspace away, keeping where its watcher had got to.
    ///
    /// Deliberately **not** `async`, and deliberately does not write snapshots.
    /// The only caller is the app quitting, from `willTerminate`, which is a
    /// synchronous callback: there is nowhere to await, and a task started here
    /// would race the process exiting. Snapshots are written as UI state
    /// settles instead — see `Workspace.scheduleSnapshotSave()` — and whenever
    /// a workspace is closed. The gap is the few hundred milliseconds of a
    /// pending debounce; closing it properly means
    /// `applicationShouldTerminate` returning `.terminateLater`.
    ///
    /// Which workspaces each window held is **not** cleared: they are open, the
    /// app is merely stopping, and the next launch brings them back.
    public func stop() {
        for (path, workspace) in states {
            if let position = workspace.position { positions[path] = position }
            workspace.stop()
        }
        states = [:]
        displayed = [:]
        holders = [:]
    }
}
