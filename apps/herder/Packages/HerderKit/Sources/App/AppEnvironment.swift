import Core
import EditorFeature
import FileTreeFeature
import Foundation
import Observation
import RepositoriesFeature
import Services

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

    /// The authoritative file and git state of the worktrees being watched.
    /// Held here rather than inside a feature because more than one pane reads
    /// it and features never import each other.
    public let worktrees: WorkspaceRegistry

    /// What the sidebar shows beside the list itself.
    public let repositoryList: RepositoriesModel

    /// The file tree of the worktree selected in the sidebar.
    public let fileTree: FileTreeModel

    /// The file open in the middle pane.
    public let editor: EditorModel

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
        self.repositoryList = RepositoriesModel(store: repositories, git: git, picker: folderPicker)
        let worktrees = WorkspaceRegistry(
            files: files, git: git, watcher: watcher, clock: clock, state: persistence.state
        )
        self.worktrees = worktrees
        self.fileTree = FileTreeModel(store: worktrees)
        self.editor = EditorModel(store: worktrees, files: files, highlighter: highlighter)
    }

    /// Opens the add-repository modal. Here rather than on the sidebar because a
    /// menu command, not just the sidebar's button, asks for it.
    public func beginAddingRepository() {
        repositoryList.beginAdding()
    }

    /// Reads the repository list, takes access to every folder, and reopens the
    /// worktrees that were open last time.
    ///
    /// `async`, because the list comes from ``StateStore``. The window renders
    /// before this finishes, showing an empty sidebar for the moment it takes.
    public func start() async {
        // Compiling the editor's grammars takes a few hundred milliseconds in
        // total, and all of it is paid the first time a file of each language
        // is opened unless it is paid here instead. Detached and unawaited:
        // nothing waits on it, and a reader who opens a file before it finishes
        // simply gets the colour a moment later.
        Task.detached { await TreeSitterHighlighter.warmUp() }

        await repositories.load()

        // Reopens the worktrees that were open last time. Cheap: none of them
        // drains until a window shows one, so this is a watcher apiece and no
        // subprocesses.
        await worktrees.restore()
    }

    /// Hands back every folder the sandbox is holding open and stops watching
    /// for changes. Balances ``start()``.
    ///
    /// Synchronous because `willTerminate` is. Nothing here writes: the
    /// repository list is saved on every change, and workspace snapshots are
    /// saved as their UI state settles.
    public func stop() {
        worktrees.stop()
        repositories.access.endAll()
    }
}
