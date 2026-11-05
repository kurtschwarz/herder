import Core
import EditorFeature
import ExplorerFeature
import Foundation
import Observation
import Services
import WorkspacesFeature

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
    /// Where the app's own state is kept. Whatever is behind it — SwiftData
    /// today, JSON files after Phase 7 — stays inside `Services`, which is why
    /// this target no longer imports SwiftData at all.
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

    /// The authoritative file and git state of the worktrees being watched.
    /// Held here rather than inside a feature because more than one pane reads
    /// it and features never import each other.
    public let worktrees: WorkspaceRegistry

    /// What the sidebar shows beside the list itself.
    public let workspaceList: WorkspacesModel

    /// The file tree of the worktree selected in the sidebar.
    public let explorer: ExplorerModel

    /// The file open in the middle pane.
    public let editor: EditorModel

    /// The live app: every service is the real one.
    ///
    /// There is no app without its repositories, and nothing useful to fall back
    /// to, so a container that cannot be opened is fatal: an in-memory store
    /// would silently throw away everything the user adds, and carrying on
    /// would invite them to add folders to a store that is not there.
    ///
    /// The store is never deleted to recover. It holds security-scoped
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
                Could not open the repository store, so Herder has nothing to \
                show and will not start.

                  store: \(path)
                  error: \(error)

                The data in that file is intact. This is a schema problem, not a \
                corrupt store: the most likely cause is a change to a @Model \
                type or to WorkspaceMigrationPlan that no longer describes what \
                is on disk. Do not delete the store to recover — it holds the \
                security-scoped bookmarks, and they cannot be regenerated \
                without re-picking every folder. Fix the schema instead, and see \
                WorkspaceMigrationTests.
                """
            )
        }

        self.init(
            files: LiveFileClient(),
            bookmarks: LiveBookmarkClient(),
            git: LiveGitClient(),
            folderPicker: LiveFolderPickerClient(),
            watcher: LiveFileWatcherClient(),
            clock: LiveClockClient(),
            persistence: persistence
        )
    }

    /// Takes every service, so tests and previews can pass fakes.
    ///
    ///
    /// `highlighter` is named here rather than defaulted inside the editor
    /// because this is the only module allowed to know a concrete service type.
    public init(
        files: any FileClient,
        bookmarks: any BookmarkClient,
        git: any GitClient,
        folderPicker: any FolderPickerClient,
        watcher: any FileWatcherClient,
        clock: any ClockClient,
        persistence: PersistenceStack,
        highlighter: any SyntaxHighlighter = TreeSitterHighlighter()
    ) {
        self.persistence = persistence
        self.state = persistence.state
        let repositories = RepositoryStore(bookmarks: bookmarks, git: git, state: persistence.state)
        self.repositories = repositories
        self.workspaceList = WorkspacesModel(store: repositories, git: git, picker: folderPicker)
        let worktrees = WorkspaceRegistry(files: files, git: git, watcher: watcher, clock: clock)
        self.worktrees = worktrees
        self.explorer = ExplorerModel(store: worktrees)
        self.editor = EditorModel(store: worktrees, files: files, highlighter: highlighter)
    }

    /// Opens the add-workspace modal. Here rather than on the sidebar because a
    /// menu command, not just the sidebar's button, asks for it.
    public func beginAddingWorkspace() {
        workspaceList.beginAdding()
    }

    /// Reads the repository list, takes access to every folder, and brings
    /// across the rows the SwiftData store used to hold.
    ///
    /// `async`, unlike the `start()` it replaces: the list now comes from
    /// ``StateStore``. The window renders before this finishes, showing an empty
    /// sidebar for the moment it takes — which is why the import happens here
    /// and not lazily behind a first read.
    public func start() async {
        // Compiling the editor's grammars takes a few hundred milliseconds in
        // total, and all of it is paid the first time a file of each language
        // is opened unless it is paid here instead. Detached and unawaited:
        // nothing waits on it, and a reader who opens a file before it finishes
        // simply gets the colour a moment later.
        Task.detached { await TreeSitterHighlighter.warmUp() }

        await repositories.load()

        // One-shot: the rows the SwiftData store used to hold carry
        // security-scoped bookmarks that cannot be regenerated, so they are
        // copied across rather than abandoned, and the table is left exactly as
        // it was. Guarded on the list being empty rather than on a flag — a
        // user who has deleted every repository since migrating must not have
        // them all come back — which also means SwiftData is not touched at all
        // on any launch after the first.
        if repositories.repositories.isEmpty {
            await repositories.adopt(persistence.legacyRepositories())
        }
    }

    /// Hands back every folder the sandbox is holding open, and stops watching
    /// for changes. Balances `start()`.
    public func stop() {
        worktrees.stop()
        repositories.access.endAll()
    }
}
