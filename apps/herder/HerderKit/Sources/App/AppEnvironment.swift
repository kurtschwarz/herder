import AgentSessionsFeature
import Core
import EditorFeature
import FileTreeFeature
import Foundation
import Observation
import RepositoriesFeature
import Services
import TerminalFeature

/// Composition root.
///
/// The only place in the codebase that names a concrete service type: ``init()``
/// builds the live ones, and the designated initializer takes whatever it is
/// given so tests and previews can pass fakes. As features arrive, construct
/// their models here and hand them to `AppView`.
///
/// This is why the app target is one file: everything that would otherwise be
/// wired up in `@main` is wired up here instead, where SwiftPM picks up new
/// files without the Xcode project having to be regenerated.
///
/// `@MainActor` is implicit: this target's default isolation is `MainActor`.
@Observable
public final class AppEnvironment {
    /// Where the app's own state is kept. What is behind it stays inside
    /// `Services`: this target has never named a storage type, which is what
    /// let JSON files replace SwiftData without a line changing here.
    private let persistence: PersistenceStack

    /// Where the app keeps its own state: open workspaces, tabs, expanded
    /// folders. App-scoped, because one store serves every window.
    ///
    /// Nothing reads it yet. It is built here from Phase 3 so that Phase 4 has
    /// something to restore from, and so the construction is proven before
    /// anything depends on it.
    public let state: any StateStore

    /// The repositories the user has adopted. Views read the list off it and
    /// Observation redraws them; nothing above here knows it is backed by
    /// ``StateStore``.
    public let repositories: RepositoryStore

    /// The agents a session can be started with, and which was used last.
    /// App-wide: Settings edits it and every window starts sessions from it.
    public let agents: AgentCatalog

    /// Every agent session there has been. App-wide, so that two windows
    /// listing one repository share one writer of its history. What each
    /// window has open is the window's own: see ``makeWindow(id:restoring:)``.
    public let sessions: AgentSessions

    /// Where windows' snapshots are kept, and which exist.
    let windows: WindowStore

    /// Windows that have claimed an identity and not yet closed.
    @ObservationIgnored
    private var liveWindows: Set<UUID> = []

    /// The same windows, to ask what each still has unsaved when the app quits.
    @ObservationIgnored
    private var openWindows: [UUID: WindowEnvironment] = [:]

    /// The authoritative file and git state of the worktrees being watched.
    /// Held here rather than inside a feature because more than one pane reads
    /// it and features never import each other.
    public let worktrees: WorkspaceRegistry

    /// What each window's models are built from. The services are the app's;
    /// the models made from them are the window's. See ``makeWindow(id:)``.
    private let git: any GitClient
    private let files: any FileClient
    private let folderPicker: any FolderPickerClient
    private let highlighter: any SyntaxHighlighter
    private let pty: any PTYClient
    private let commands: any CommandClient
    private let clock: any ClockClient
    private let leftovers: (any LeftoverAgentClient)?
    private let opencode: (any OpencodeIntegrationClient)?

    /// Where this copy of the app is running from. Nothing outside the
    /// bundle is pointed at it until it is `.settled`.
    let location: AppLocation

    /// What finds and installs new releases, for the menu and Settings.
    /// `nil` when there is nothing to update from, which a debug build is
    /// treated as: it would always find a release newer than itself.
    public let updater: (any UpdaterClient)?

    /// The live app: every service is the real one.
    ///
    /// There is no app without its repositories, and nothing useful to fall back
    /// to, so a store that cannot be opened is fatal: carrying on would hand the
    /// user an empty sidebar and invite them to add folders to state that is not
    /// there.
    ///
    /// Nothing is ever deleted to recover. The state holds security-scoped
    /// bookmarks, which cannot be regenerated without the user re-picking every
    /// folder, so a store that will not open is a bug to fix rather than state
    /// to discard — hence the message naming the file and saying so.
    public convenience init() {
        let persistence: PersistenceStack
        do {
            persistence = try PersistenceStack.live()
        } catch {
            let path = (try? PersistenceStack.storeURL().path(percentEncoded: false)) ?? "unknown"
            fatalError(
                """
                Could not open Herder's state, so it has nothing to show and \
                will not start.

                  state: \(path)
                  error: \(error)

                Do not delete anything under that folder to recover — it holds \
                the security-scoped bookmarks, and they cannot be regenerated \
                without re-picking every folder. The only way this fails is \
                Application Support being unreachable or unwritable, because \
                nothing is read at this point: an absent state file is a first \
                launch, not an error.
                """
            )
        }

        let opencode = Bundle.main.resourceURL.map { resources in
            LiveOpencodeIntegrationClient(
                resources: resources.appending(path: "opencode", directoryHint: .isDirectory),
                config: LiveOpencodeIntegrationClient.configDirectory(
                    environment: ProcessInfo.processInfo.environment, home: .homeDirectory
                )
            )
        }

        #if DEBUG
        let updater: (any UpdaterClient)? = nil
        #else
        let updater: (any UpdaterClient)? = SparkleUpdaterClient()
        #endif

        self.init(
            files: LiveFileClient(),
            bookmarks: LiveBookmarkClient(),
            git: LiveGitClient(),
            folderPicker: LiveFolderPickerClient(),
            watcher: LiveFileWatcherClient(),
            clock: LiveClockClient(),
            persistence: persistence,
            leftovers: LiveLeftoverAgentClient(),
            opencode: opencode,
            updater: updater
        )
    }

    /// Takes every service, so tests and previews can pass fakes.
    ///
    ///
    /// `highlighter` is named here rather than defaulted inside the editor
    /// because this is the only module allowed to know a concrete service type.
    ///
    /// `leftovers` is `nil` unless asked for, so a test or a preview never
    /// ends a real process the developer's own Herder left behind. `opencode`
    /// is `nil` for the same reason: a test must not link into the
    /// developer's own opencode config. `bundle` is where the app is running
    /// from, which decides whether `opencode` is asked at all. `updater` is
    /// `nil` so that nothing checks GitHub from a test.
    public init(
        files: any FileClient,
        bookmarks: any BookmarkClient,
        git: any GitClient,
        folderPicker: any FolderPickerClient,
        watcher: any FileWatcherClient,
        clock: any ClockClient,
        persistence: PersistenceStack,
        highlighter: any SyntaxHighlighter = TreeSitterHighlighter(),
        pty: any PTYClient = LivePTYClient(),
        commands: any CommandClient = LiveCommandClient(),
        leftovers: (any LeftoverAgentClient)? = nil,
        opencode: (any OpencodeIntegrationClient)? = nil,
        updater: (any UpdaterClient)? = nil,
        bundle: URL = Bundle.main.bundleURL
    ) {
        self.persistence = persistence
        self.state = persistence.state
        let snapshots = AppSnapshotStore(state: persistence.state)
        let repositories = RepositoryStore(
            bookmarks: bookmarks, git: git, state: persistence.state, snapshots: snapshots
        )
        self.repositories = repositories
        self.windows = WindowStore(snapshots: snapshots, state: persistence.state)
        self.agents = AgentCatalog(state: persistence.state)
        self.sessions = AgentSessions(git: git, state: persistence.state, clock: clock)
        self.worktrees = WorkspaceRegistry(
            files: files, git: git, watcher: watcher, clock: clock, state: persistence.state
        )
        self.git = git
        self.files = files
        self.folderPicker = folderPicker
        self.highlighter = highlighter
        self.pty = pty
        self.commands = commands
        self.clock = clock
        self.leftovers = leftovers
        self.opencode = opencode
        self.updater = updater
        self.location = AppLocation(bundle: bundle)
    }

    /// A window's own state and the models behind its panes.
    ///
    /// Built here because this is the only module allowed to name the services
    /// they are made from. Each call makes a new set, which is the point: two
    /// windows must not share an editor.
    func makeWindow(id: UUID = UUID(), restoring snapshot: WindowSnapshot? = nil) -> WindowEnvironment {
        let list = WindowRepositories(store: repositories, members: snapshot?.repositories ?? [])
        return WindowEnvironment(
            id: id,
            repositories: list,
            repositoryList: RepositoriesModel(repositories: list, git: git, picker: folderPicker),
            fileTree: FileTreeModel(store: worktrees),
            editor: EditorModel(store: worktrees, files: files, highlighter: highlighter),
            terminal: TerminalModel(pty: pty, clock: clock),
            agentPanel: AgentPanelModel(
                pty: pty, commands: commands, clock: clock, catalog: agents,
                sessions: WindowAgentSessions(store: sessions, window: id)
            ),
            worktrees: worktrees,
            windows: windows,
            restoring: snapshot
        )
    }

    /// Gives a window that has just appeared its identity and its state.
    ///
    /// `stored` is the id the system kept for this window, which it hands back
    /// only when it restores the scene. A window without one is either new or
    /// had its scene lost, and the two look alike: quitting with every window
    /// closed loses them all. So when no other window is open, it adopts the one
    /// used last, and a relaunch never looks like the app forgot everything.
    /// With another window open it is a blank slate, which is what ⌘N means.
    ///
    /// Waits for ``start()``, because the folder access a workspace needs is
    /// taken there and a window's task may run before the app's.
    func claimWindow(id stored: UUID?) async -> WindowEnvironment {
        await start()
        let index = await windows.index()

        // No suspension from here to the insert, so two windows appearing at
        // once cannot both adopt the same snapshot.
        let id: UUID
        if let stored, !liveWindows.contains(stored) {
            id = stored
        } else if liveWindows.isEmpty, let adopted = index.first {
            id = adopted
        } else {
            id = UUID()
        }
        liveWindows.insert(id)

        let window = makeWindow(id: id, restoring: await windows.load(id))
        openWindows[id] = window
        return window
    }

    /// A window was closed by the user, as opposed to the app quitting.
    func close(_ window: WindowEnvironment) async {
        liveWindows.remove(window.id)
        openWindows[window.id] = nil
        await window.didClose()
    }

    /// The files with unsaved edits in any window, for the quit prompt.
    public var unsavedFiles: [String] {
        openWindows.values.flatMap(\.editor.unsavedFiles)
    }

    /// Whether any window has a terminal open.
    public var hasTerminals: Bool {
        openWindows.values.contains { $0.terminal.hasTerminals }
    }

    /// What every window's terminals are running, for the quit prompt.
    public func runningCommands() async -> [String] {
        var commands: [String] = []
        for window in openWindows.values { commands += await window.terminal.runningCommands() }
        return commands
    }

    /// Saves every window's unsaved files. `false` if any would not save, in
    /// which case its window shows why and the app should not quit.
    public func saveAll() async -> Bool {
        for window in openWindows.values {
            guard await window.editor.saveAll() else { return false }
        }
        return true
    }

    /// Reads the repository list and takes access to every folder. Windows reopen
    /// their own worktrees when they claim themselves — see ``claimWindow(id:)``.
    ///
    /// `async`, because the list comes from ``StateStore``. The window renders
    /// before this finishes, showing an empty sidebar for the moment it takes.
    ///
    /// Once per environment however many windows ask: each window runs this
    /// from its own task, and they all join the same one.
    public func start() async {
        let task = starting ?? Task { await begin() }
        starting = task
        await task.value
    }

    @ObservationIgnored
    private var starting: Task<Void, Never>?

    private func begin() async {
        // Compiling the editor's grammars takes a few hundred milliseconds in
        // total, and all of it is paid the first time a file of each language
        // is opened unless it is paid here instead. Detached and unawaited:
        // nothing waits on it, and a reader who opens a file before it finishes
        // simply gets the colour a moment later.
        Task.detached { await TreeSitterHighlighter.warmUp() }
        // Agents a crash left running. Unawaited too: it waits two seconds
        // for a stubborn one, and nothing here depends on it.
        if let leftovers { Task { await leftovers.endLeftovers() } }
        // The theme and plugin opencode needs, linked from the bundle. Not
        // from a disk image or a translocated copy, whose links would dangle
        // by the next launch: `AppDelegate` offers to move the app instead.
        if let opencode, location == .settled { await opencode.install() }

        await agents.load()
        await repositories.load()
    }

    /// Hands back every folder the sandbox is holding open and stops watching
    /// for changes. Balances ``start()``.
    ///
    /// Synchronous because `willTerminate` is. Nothing here writes: the
    /// repository list is saved on every change, and workspace snapshots are
    /// saved as their UI state settles.
    ///
    /// Agents are ended here rather than left to the terminal closing with
    /// the app, which some do not notice.
    public func stop() {
        for window in openWindows.values { window.agentPanel.terminateForQuit() }
        worktrees.stop()
        repositories.access.endAll()
    }
}
