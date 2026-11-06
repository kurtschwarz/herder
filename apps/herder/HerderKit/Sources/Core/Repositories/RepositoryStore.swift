import Foundation
import Observation

/// The repositories the user has adopted, and everything that can be done to
/// the pool.
///
/// App-scoped: one pool, however many windows. Each window lists some of it —
/// see ``WindowRepositories`` — but a folder is adopted once, with one bookmark
/// and one hold on the sandbox, whichever windows show it. The rules about
/// eligibility, naming and folder access live here instead of being re-derived
/// at each call site.
///
/// Views read ``repositories`` and are redrawn by Observation. That is what
/// replaced `@Query`: the list used to come from SwiftData, read directly in
/// the sidebar, with every change written through the same `mainContext` the
/// view was reading so it showed with no round trip. Owning the array gives the
/// same immediacy without a feature having to know what a `ModelContext` is.
///
/// `@MainActor` explicitly, because `Core` keeps the nonisolated default. The
/// I/O behind it — git, bookmarks, the state store — is `async` and runs off
/// this actor.
@MainActor
@Observable
public final class RepositoryStore {
    /// Every folder adopted, in the order they were. Mutated only through the
    /// methods below.
    public private(set) var repositories: [Repository] = []

    private let bookmarks: any BookmarkClient
    private let git: any GitClient
    private let snapshots: AppSnapshotStore

    /// The folder access held open on behalf of these repositories.
    public let access: RepositoryAccess

    /// `snapshots` is shared with whatever else writes the app snapshot, so
    /// that two edits to it cannot overwrite each other. Left out, the store
    /// makes its own, which is right when nothing else writes.
    public init(
        bookmarks: any BookmarkClient,
        git: any GitClient,
        state: any StateStore,
        snapshots: AppSnapshotStore? = nil
    ) {
        self.bookmarks = bookmarks
        self.git = git
        self.snapshots = snapshots ?? AppSnapshotStore(state: state)
        self.access = RepositoryAccess(bookmarks: bookmarks)
    }

    public subscript(id: UUID) -> Repository? {
        repositories.first { $0.id == id }
    }

    // MARK: - Loading

    /// Reads the list, resolves every bookmark and takes access to the folders.
    /// Called once at launch, before anything reads a repository's files.
    ///
    /// A folder that cannot be reached — deleted, on an unmounted volume, access
    /// revoked — keeps its place and comes back marked unavailable. Dropping it
    /// would be data loss from the user's side for something as ordinary as an
    /// external drive being unplugged.
    public func load() async {
        repositories = Self.sorted(await snapshots.read().repositories)
        openFolders()
        // The paths and remade bookmarks resolving may have produced are worth
        // keeping; nothing else about the list changed.
        await save()
    }

    /// Resolves each bookmark and takes access. Separated from ``load()`` so the
    /// legacy import can hand rows straight in.
    private func openFolders() {
        for index in repositories.indices {
            let id = repositories[index].id

            guard let resolved = try? bookmarks.resolve(repositories[index].bookmark) else {
                access.end(for: id)
                repositories[index].isAvailable = false
                continue
            }

            // A stale bookmark still resolves, but only for now: remake it while
            // the folder is in reach.
            if resolved.isStale, let remade = try? bookmarks.makeBookmark(for: resolved.url) {
                repositories[index].bookmark = remade
            }

            let path = resolved.url.path(percentEncoded: false)
            if repositories[index].path != path { repositories[index].path = path }

            repositories[index].isAvailable = access.begin(resolved.url, for: id)
        }
    }

    // MARK: - Changing

    /// Whether a folder could be adopted, without adopting it. Runs exactly the
    /// checks ``add(url:name:)`` runs and throws exactly what it would, so the
    /// UI can say no as soon as a folder is picked instead of when the user
    /// commits.
    ///
    /// A folder already in the pool is fine: it is joined, not refused. Whether
    /// *this window* already lists it is the window's to say.
    ///
    /// Returns what git made of the folder, which is what the default name
    /// depends on.
    @discardableResult
    public func validate(url: URL) async throws -> GitRepositoryKind {
        try await repositoryKind(of: url.standardizedFileURL)
    }

    /// Adopts a folder, or hands back the record it already has.
    ///
    /// A folder is adopted once. Picking one that is already in the pool —
    /// because another window lists it — joins that record rather than making a
    /// second, which would mean a second bookmark and a second hold on the
    /// sandbox for one folder. The name given is then ignored: the record
    /// already has the one the user chose.
    ///
    /// Passing no name takes the folder's own, which is what the sidebar shows
    /// until the user renames it. Validates again rather than trusting an
    /// earlier ``validate(url:)``: the folder may have changed since it was
    /// picked.
    @discardableResult
    public func add(url: URL, name: String? = nil) async throws -> Repository {
        let url = url.standardizedFileURL
        let kind = try await validate(url: url)
        if let existing = pooled(holding: url) { return existing }

        var repository = Repository(
            name: name ?? Self.defaultName(for: url, kind: kind),
            path: url.path(percentEncoded: false),
            bookmark: try bookmarks.makeBookmark(for: url)
        )
        repository.isAvailable = access.begin(url, for: repository.id)
        repositories.append(repository)
        await save()
        return repository
    }

    /// Points an existing repository at a folder the user found again, after its
    /// own went missing. Keeps the name and identity: this is the same
    /// repository, somewhere else.
    public func relocate(_ repository: Repository, to url: URL) async throws {
        guard let index = index(of: repository) else { return }
        let url = url.standardizedFileURL
        try await repositoryKind(of: url)

        repositories[index].bookmark = try bookmarks.makeBookmark(for: url)
        repositories[index].path = url.path(percentEncoded: false)
        repositories[index].isAvailable = access.begin(url, for: repository.id)
        await save()
    }

    /// Renames a repository. A blank name keeps the current one: the user had
    /// already chosen something, and an empty row in the sidebar is never what
    /// they meant. Duplicates are fine, since two checkouts of one repository
    /// legitimately share a name and identity is the `id`.
    public func rename(_ repository: Repository, to name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = index(of: repository) else { return }
        guard !name.isEmpty, name != repositories[index].name else { return }
        repositories[index].name = name
        await save()
    }

    /// Forgets a repository outright: the app's record of it and its hold on
    /// the sandbox go, and every window that listed it loses it. The folder on
    /// disk is untouched.
    ///
    /// Not what a window does to take a repository out of its own sidebar —
    /// that is ``WindowRepositories/remove(_:)``, which leaves the record, its
    /// bookmark and its folder access where they are.
    public func delete(_ repository: Repository) async {
        guard let index = index(of: repository) else { return }
        access.end(for: repository.id)
        repositories.remove(at: index)
        await save()
    }

    // MARK: - Persisting

    /// Writes the list, leaving everything else in the snapshot alone.
    ///
    /// Read-modify-write rather than building a fresh snapshot: the app's other
    /// state shares this key, and replacing the whole thing would drop it.
    public func save() async {
        let list = repositories
        // A failure here loses the user's list, so it is not swallowed quietly.
        do {
            try await snapshots.update { $0.repositories = list }
        } catch {
            assertionFailure("Could not save the repository list: \(error)")
        }
    }

    // MARK: - Rules

    /// What git makes of the folder, refusing anything that cannot be a
    /// repository.
    @discardableResult
    private func repositoryKind(of url: URL) async throws -> GitRepositoryKind {
        let kind = try await git.repositoryKind(at: url)

        switch kind {
        case .mainWorkingTree, .bare:
            return kind
        case .linkedWorktree(let mainRepository):
            throw RepositoryStoreError.isLinkedWorktree(mainRepository: mainRepository)
        case .notARepository:
            throw RepositoryStoreError.notAGitRepository(url)
        }
    }

    /// The record for the folder at `url`, if it has been adopted.
    ///
    /// Compares where each existing repository's bookmark points now, not the
    /// cached path: the same folder reached by a new path is still the same
    /// folder. A repository whose bookmark no longer resolves falls back to its
    /// cached path rather than silently matching nothing.
    public func pooled(holding url: URL) -> Repository? {
        let url = url.standardizedFileURL
        return repositories.first { repository in
            let resolved = (try? bookmarks.resolve(repository.bookmark))?.url
                ?? URL(filePath: repository.path)
            return resolved.standardizedFileURL == url
        }
    }

    private func index(of repository: Repository) -> Int? {
        repositories.firstIndex { $0.id == repository.id }
    }

    private static func sorted(_ repositories: [Repository]) -> [Repository] {
        repositories.sorted { $0.addedAt < $1.addedAt }
    }

    /// The folder's own name, less the `.git` suffix a bare repository carries:
    /// that suffix is a repository-layout detail, not something to show.
    public static func defaultName(for url: URL, kind: GitRepositoryKind) -> String {
        let component = url.lastPathComponent
        guard kind == .bare, component.hasSuffix(".git"), component != ".git" else {
            return component
        }
        return String(component.dropLast(".git".count))
    }
}
