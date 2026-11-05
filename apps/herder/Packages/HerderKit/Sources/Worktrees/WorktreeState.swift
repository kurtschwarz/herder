import Clients
import Foundation
import Models
import Observation

/// Everything the app knows about one worktree's files, kept fresh by a file
/// watcher.
///
/// The single source of truth for a worktree: the folders that have been read
/// and what git says about the whole tree. Panes read it instead of each
/// growing a reader of its own, which is what makes a second one — a status
/// gutter, a dirty marker in the sidebar — cost nothing extra.
///
/// Isolated to the main actor like every other model here, not an `actor`: the
/// state is read on every redraw, and an `actor` would put an `await` in front
/// of each of those. What must not block the main thread is the disk and
/// subprocess work, and that is `@concurrent` inside the clients.
///
/// ## Surviving an event storm
///
/// An install or a build writes thousands of files, and a refresh costs a
/// subprocess. Five things keep that bounded, in the order they apply:
///
/// 1. The watcher's own latency batches a burst before this code runs at all.
/// 2. Folders nothing has read are dropped here. This is the big one: a storm
///    happens almost entirely inside `node_modules`, `.build` and `dist`,
///    which nobody has open, so the events die at one set lookup each.
/// 3. What survives goes into a dirty set with one drain in flight, so work
///    per drain is bounded by how many folders are open, not by how many
///    events arrived.
/// 4. The drain waits for the writes to stop, but never longer than
///    ``ceiling``, so a long build neither thrashes nor starves.
/// 5. A drain asks git once, for the whole repository. That is the structural
///    one: it is a hard ceiling of about one subprocess a second whatever the
///    file system is doing.
@Observable
public final class WorktreeState {
    /// What reading a folder came to. A failed read is its own state because an
    /// empty list would claim the folder has nothing in it.
    public enum Listing: Equatable {
        case loaded([DirectoryEntry])
        case unreadable
    }

    /// Git's own folders: machinery, not the user's files.
    private static let hidden: Set<String> = [".git", ".bare"]

    /// How long after the last change a drain waits for quiet.
    static let debounce = Duration.milliseconds(150)

    /// How long a drain will be put off by continuing changes before it
    /// happens anyway. Without it a build that never goes quiet would hold the
    /// refresh off for as long as it ran.
    static let ceiling = Duration.seconds(1)

    public let root: PathKey

    /// Where staging writes. Changes here are the only sign of a `git add`, and
    /// for a linked worktree it is not under ``root`` at all.
    private let gitDirectory: PathKey?

    private let files: any FileClient
    private let git: any GitClient
    private let watcher: any FileWatcherClient
    private let clock: any ClockClient

    public private(set) var listings: [PathKey: Listing] = [:]
    public private(set) var status: WorktreeStatus = .empty

    /// False once the worktree's folder has gone from under the watcher, which
    /// `git worktree remove` in a terminal does. Nothing tries to render a
    /// half-dead tree after that.
    public private(set) var isAvailable = true

    /// Who hears about changes to this worktree. See ``observe(onChange:onMove:)``.
    private struct Observer {
        var onChange: () -> Void
        var onMove: (PathKey, PathKey) -> Void
    }

    private var observers: [UUID: Observer] = [:]

    /// Held by whoever is listening, and cancelled when they stop. Cancelling
    /// is explicit: nothing here is told when its holder goes away.
    public final class Registration {
        private weak var state: WorktreeState?
        private let id: UUID

        fileprivate init(state: WorktreeState, id: UUID) {
            self.state = state
            self.id = id
        }

        public func cancel() {
            state?.observers[id] = nil
            state = nil
        }
    }

    /// Calls `onChange` after the listings or the status change, and `onMove`
    /// when a file or folder is renamed through ``move(_:to:)``, with the old
    /// and the new path. The change signal carries nothing else: a listener
    /// re-reads what it cares about.
    ///
    /// Capture the listener as `[weak self]`, or the state would hold a
    /// listener which holds the state.
    public func observe(
        onChange: @escaping () -> Void,
        onMove: @escaping (PathKey, PathKey) -> Void = { _, _ in }
    ) -> Registration {
        let id = UUID()
        observers[id] = Observer(onChange: onChange, onMove: onMove)
        return Registration(state: self, id: id)
    }

    private var dirty: Set<PathKey> = []
    private var needsFullScan = false
    private var firstChangeAt: ContinuousClock.Instant?
    private var lastChangeAt: ContinuousClock.Instant?
    private var drain: Task<Void, Never>?

    /// Whether a drain may run. Changes still accumulate while it may not: the
    /// worst storms happen while the user is in a terminal watching the build
    /// that is causing them, not looking at this window.
    private var isDraining = true

    private var watching: Task<Void, Never>?

    /// Set by ``stop()``. Cancelling the watching task is not enough on its
    /// own: a batch already delivered to its stream is handed over without the
    /// task ever suspending, so cancellation is not noticed until after it has
    /// been acted on.
    private var isStopped = false

    /// Where the watcher has got to, so a stream can be started again without
    /// missing what happened in between.
    public private(set) var position: FileWatcherPosition?

    init(
        root: PathKey,
        gitDirectory: PathKey?,
        from position: FileWatcherPosition?,
        files: any FileClient,
        git: any GitClient,
        watcher: any FileWatcherClient,
        clock: any ClockClient
    ) {
        self.root = root
        self.gitDirectory = gitDirectory
        self.position = position
        self.files = files
        self.git = git
        self.watcher = watcher
        self.clock = clock
    }

    // MARK: - Reading

    public func listing(of folder: PathKey) -> Listing? {
        listings[folder]
    }

    /// Whether `path` is still there, as far as the folder that holds it
    /// says. `nil` when that folder has not been read, so nothing here knows
    /// either way; leaving what is probably fine alone beats dropping it.
    public func exists(_ path: PathKey) -> Bool? {
        guard
            let parent = path.parent,
            case .loaded(let entries)? = listings[parent]
        else { return nil }
        return entries.contains { $0.name == path.name }
    }

    /// The worktree's own folder name followed by the names between it and
    /// `path`, for a breadcrumb. Empty when `path` is not inside.
    public func components(of path: PathKey) -> [String] {
        guard path.isInside(root) else { return [] }
        return [root.name] + path.path.dropFirst(root.path.count).split(separator: "/").map(String.init)
    }

    /// Reads `folder` the first time it is asked for, and not again: a
    /// repository's `node_modules` costs nothing until somebody looks inside.
    public func open(_ folder: PathKey) async {
        guard listings[folder] == nil else { return }
        await read(folder)
        notify()
    }

    /// Re-reads every folder that has been read, then asks git about the tree.
    ///
    /// The listings go up before git is asked, so a slow git delays the marks
    /// and not the folders.
    public func refresh() async {
        guard isAvailable else { return }
        // A set, because the root is itself one of the folders that have been
        // read and would otherwise be read twice.
        for folder in Set([root] + listings.keys).sorted() {
            await read(folder)
        }
        await readStatus()
        notify()
    }

    private func read(_ folder: PathKey) async {
        let entries: [DirectoryEntry]
        do {
            entries = Self.sorted(try await files.children(of: folder.url))
        } catch {
            // The task that asked was cancelled, which says nothing about the
            // folder.
            guard !Task.isCancelled, isAvailable else { return }
            listings[folder] = .unreadable
            return
        }
        guard isAvailable else { return }
        // A listing that came back the same is not assigned. Writing to a file
        // inside an open folder changes nothing about what is in that folder,
        // so a build in watch mode would otherwise invalidate the whole tree
        // over and over for no visible difference.
        guard listings[folder] != .loaded(entries) else { return }
        listings[folder] = .loaded(entries)
    }

    private func readStatus() async {
        let answer: GitWorktreeStatus
        do {
            answer = try await git.status(in: root.url)
        } catch {
            // Git could not be asked, which says nothing about the files: keep
            // what is already marked rather than calling the tree clean.
            return
        }
        guard isAvailable else { return }
        let derived = WorktreeStatus(answer)
        guard status != derived else { return }
        status = derived
    }

    // MARK: - Changing

    /// Makes an empty file, or a folder, and shows it. Throws what the disk
    /// said, so a caller can leave a name field up with the reason.
    public func create(_ url: URL, isDirectory: Bool) async throws {
        try await files.create(url, isDirectory: isDirectory)
        await refresh()
    }

    /// Moves a file or folder and shows the result. What was read under a
    /// renamed folder stays read under its new name, so opening it again does
    /// not re-read the whole subtree.
    public func move(_ source: URL, to destination: URL) async throws {
        try await files.move(source, to: destination)
        let old = PathKey(canonical: source.path(percentEncoded: false))
        let new = PathKey(canonical: destination.path(percentEncoded: false))
        listings = Dictionary(
            listings.map { (Self.moved($0.key, from: old, to: new), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        // Before the refresh, which tells listeners to re-read: they must know
        // where the file went by then, or the re-read finds it gone.
        for observer in Array(observers.values) { observer.onMove(old, new) }
        await refresh()
    }

    /// `path` rebased onto `new` if it is `old` or lies inside it.
    public static func moved(_ path: PathKey, from old: PathKey, to new: PathKey) -> PathKey {
        guard path.isInside(old) else { return path }
        if path == old { return new }
        return new.appending(String(path.path.dropFirst(old.path.count + 1)))
    }

    /// Folders before files, each group by name regardless of case.
    private static func sorted(_ entries: [DirectoryEntry]) -> [DirectoryEntry] {
        entries
            .filter { !hidden.contains($0.url.lastPathComponent) }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private func notify() {
        for observer in Array(observers.values) { observer.onChange() }
    }

    // MARK: - Watching

    /// Whether a drain may run. Suspended while nobody is looking at this
    /// worktree; changes keep accumulating either way.
    public func setDraining(_ enabled: Bool) {
        guard enabled != isDraining else { return }
        isDraining = enabled
        if enabled, hasWork { scheduleDrain() }
    }

    func stop() {
        isStopped = true
        watching?.cancel()
        watching = nil
        drain?.cancel()
        drain = nil
    }

    func beginWatching() {
        guard watching == nil else { return }
        // One stream over both roots: the working tree, and the git directory
        // where staging writes.
        let roots = ([root] + (gitDirectory.map { [$0] } ?? [])).map(\.url)
        let stream = watcher.watch(roots, from: position)
        watching = Task { [weak self] in
            for await batch in stream {
                guard let self else { return }
                note(batch)
            }
        }
    }

    private var hasWork: Bool {
        needsFullScan || !dirty.isEmpty
    }

    private func note(_ batch: FileChangeBatch) {
        guard isAvailable, !isStopped else { return }
        position = batch.position

        if batch.vanishedRoots.contains(where: { root.isInside($0) }) {
            vanish()
            return
        }

        var matters = batch.needsFullScan
        if batch.needsFullScan {
            // The watcher dropped events, so which folders changed is not
            // known and the whole tree has to be read again.
            needsFullScan = true
        }
        for folder in batch.folders {
            if folder == gitDirectory {
                // Nothing in the working tree changed, but what is staged may
                // have. The status call a drain makes anyway is the answer.
                matters = true
            } else if listings[folder] != nil {
                dirty.insert(folder)
                matters = true
            }
        }
        guard matters else { return }

        let now = clock.now
        if firstChangeAt == nil { firstChangeAt = now }
        lastChangeAt = now
        scheduleDrain()
    }

    private func scheduleDrain() {
        guard isDraining, drain == nil else { return }
        drain = Task { [weak self] in
            await self?.runDrain()
            guard let self else { return }
            drain = nil
            // However many changes arrived while that drain was out, they
            // collapse into exactly one more.
            if hasWork { scheduleDrain() }
        }
    }

    private func runDrain() async {
        await waitForQuiet()
        guard !Task.isCancelled, isAvailable else { return }

        let folders = dirty
        let full = needsFullScan
        dirty = []
        needsFullScan = false
        firstChangeAt = nil
        lastChangeAt = nil

        if full {
            // Falling back to exactly what a window coming forward used to do.
            // The storm path is the code that was always here.
            await refresh()
            return
        }
        for folder in folders.sorted() {
            await read(folder)
        }
        await readStatus()
        notify()
    }

    /// Waits for the writes to stop, or for the ceiling, whichever comes first.
    private func waitForQuiet() async {
        while let last = lastChangeAt, let first = firstChangeAt {
            let deadline = min(last.advanced(by: Self.debounce), first.advanced(by: Self.ceiling))
            let remaining = clock.now.duration(to: deadline)
            guard remaining > .zero else { return }
            do {
                try await clock.sleep(for: remaining)
            } catch {
                return
            }
        }
    }

    private func vanish() {
        isAvailable = false
        listings = [:]
        status = .empty
        dirty = []
        needsFullScan = false
        stop()
        notify()
    }
}
