import Core
import Foundation
import SwiftData

/// Everything that can be done to the list of workspaces.
///
/// Views read workspaces with `@Query`; every change goes through here, so the
/// rules about eligibility, naming, ordering and folder access live in one place
/// instead of being re-derived at each call site.
public struct WorkspaceStore {
    private let context: ModelContext
    private let bookmarks: any BookmarkClient
    private let git: any GitClient

    /// The folder access held open on behalf of these workspaces.
    public let access: WorkspaceAccess

    public init(context: ModelContext, bookmarks: any BookmarkClient, git: any GitClient) {
        self.context = context
        self.bookmarks = bookmarks
        self.git = git
        self.access = WorkspaceAccess(bookmarks: bookmarks)
    }

    /// Every workspace in sidebar order.
    public func workspaces() throws -> [Workspace] {
        try context.fetch(
            FetchDescriptor<Workspace>(
                sortBy: [SortDescriptor(\.order), SortDescriptor(\.addedAt)]
            )
        )
    }

    /// Whether a folder could be added, without adding it. Runs exactly the
    /// checks `add` runs and throws exactly what it would, so the UI can say no
    /// as soon as a folder is picked instead of when the user commits.
    ///
    /// Returns what git made of the folder, which is what the default name
    /// depends on.
    @discardableResult
    public func validate(url: URL) async throws -> GitRepositoryKind {
        let url = url.standardizedFileURL
        let kind = try await repositoryKind(of: url)
        guard try !isAlreadyAWorkspace(url) else { throw WorkspaceStoreError.alreadyOpen(url) }
        return kind
    }

    /// Adopts a folder, appending it to the bottom of the sidebar.
    ///
    /// Passing no name takes the folder's own, which is what the sidebar shows
    /// until the user renames it. Validates again rather than trusting an
    /// earlier `validate`: the folder may have changed since it was picked.
    @discardableResult
    public func add(url: URL, name: String? = nil) async throws -> Workspace {
        let url = url.standardizedFileURL
        let kind = try await validate(url: url)

        let workspace = Workspace(
            name: name ?? Self.defaultName(for: url, kind: kind),
            path: url.path(percentEncoded: false),
            bookmark: try bookmarks.makeBookmark(for: url),
            order: try nextOrder()
        )
        context.insert(workspace)
        try context.save()
        workspace.isAvailable = access.begin(url, for: workspace.id)
        return workspace
    }

    /// Resolves every workspace's folder and takes access to it. Called once at
    /// launch, before anything reads a workspace's files.
    ///
    /// A folder that cannot be reached — deleted, on an unmounted volume, access
    /// revoked — keeps its row and comes back marked unavailable. Dropping it
    /// would be data loss from the user's side for something as ordinary as an
    /// external drive being unplugged.
    @discardableResult
    public func open() throws -> [Workspace] {
        let workspaces = try workspaces()

        for workspace in workspaces {
            guard let resolved = try? bookmarks.resolve(workspace.bookmark) else {
                access.end(for: workspace.id)
                workspace.isAvailable = false
                continue
            }

            // A stale bookmark still resolves, but only for now: remake it while
            // the folder is in reach.
            if resolved.isStale, let remade = try? bookmarks.makeBookmark(for: resolved.url) {
                workspace.bookmark = remade
            }

            let path = resolved.url.path(percentEncoded: false)
            if workspace.path != path { workspace.path = path }

            workspace.isAvailable = access.begin(resolved.url, for: workspace.id)
        }

        try context.save()
        return workspaces
    }

    /// Points an existing workspace at a folder the user found again, after its
    /// own went missing. Keeps the workspace's name, order and identity: this is
    /// the same workspace, somewhere else.
    public func relocate(_ workspace: Workspace, to url: URL) async throws {
        let url = url.standardizedFileURL
        try await repositoryKind(of: url)

        workspace.bookmark = try bookmarks.makeBookmark(for: url)
        workspace.path = url.path(percentEncoded: false)
        try context.save()
        workspace.isAvailable = access.begin(url, for: workspace.id)
    }

    /// Renames a workspace. A blank name keeps the current one: the user had
    /// already chosen something, and an empty row in the sidebar is never what
    /// they meant. Duplicates are fine, since two checkouts of one repository
    /// legitimately share a name and identity is the `id`.
    public func rename(_ workspace: Workspace, to name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != workspace.name else { return }
        workspace.name = name
        try context.save()
    }

    /// Forgets a workspace. The folder on disk is untouched: only the app's
    /// record of it and its hold on the sandbox go away.
    ///
    /// The survivors keep their numbers. Closing the gap would renumber rows the
    /// user never moved, and an undone delete would then land on a number a
    /// sibling had taken. A gap in the sequence costs nothing: the sort only
    /// cares about the relative order.
    public func delete(_ workspace: Workspace) throws {
        access.end(for: workspace.id)
        context.delete(workspace)
        try context.save()
    }

    /// Puts the workspaces in the given order, renumbering every row in one
    /// save. Renumbering wholesale is a handful of assignments at this size, and
    /// leaves no room for the numbering to go inconsistent.
    public func reorder(to ordered: [Workspace]) throws {
        for (index, workspace) in ordered.enumerated() where workspace.order != index {
            workspace.order = index
        }
        try context.save()
    }

    /// What git makes of the folder, refusing anything that cannot be a
    /// workspace.
    @discardableResult
    private func repositoryKind(of url: URL) async throws -> GitRepositoryKind {
        let kind = try await git.repositoryKind(at: url)

        switch kind {
        case .mainWorkingTree, .bare:
            return kind
        case .linkedWorktree(let mainRepository):
            throw WorkspaceStoreError.isLinkedWorktree(mainRepository: mainRepository)
        case .notARepository:
            throw WorkspaceStoreError.notAGitRepository(url)
        }
    }

    /// Compares where each existing workspace's bookmark points now, not the
    /// cached path: the same folder reached by a new path is still the same
    /// folder. A workspace whose bookmark no longer resolves falls back to its
    /// cached path rather than silently matching nothing.
    private func isAlreadyAWorkspace(_ url: URL) throws -> Bool {
        try workspaces().contains { workspace in
            let resolved = (try? bookmarks.resolve(workspace.bookmark))?.url
                ?? URL(filePath: workspace.path)
            return resolved.standardizedFileURL == url
        }
    }

    private func nextOrder() throws -> Int {
        (try workspaces().last?.order).map { $0 + 1 } ?? 0
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
