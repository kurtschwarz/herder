import Foundation
import Observation

/// One repository as one window lists it: which, where, and whether it is
/// folded.
///
/// These are facts about a sidebar and there is one per window, so they cannot
/// live on the ``Repository`` they refer to. Its position in the array is its
/// position in the sidebar.
public struct RepositoryMembership: Codable, Sendable, Equatable, Identifiable {
    public var repositoryID: UUID

    /// Whether this window is hiding the repository's worktrees. Folded rather
    /// than unfolded, so a repository the user has never touched — and one
    /// added later — starts open.
    public var isCollapsed: Bool

    /// Whether the sidebar's workspace selector has left this repository out.
    /// Hidden rather than shown, for the same reason as ``isCollapsed``: one
    /// added later starts on screen.
    public var isHidden: Bool

    public var id: UUID { repositoryID }

    public init(repositoryID: UUID, isCollapsed: Bool = false, isHidden: Bool = false) {
        self.repositoryID = repositoryID
        self.isCollapsed = isCollapsed
        self.isHidden = isHidden
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repositoryID = try container.decode(UUID.self, forKey: .repositoryID)
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }
}

/// The repositories one window lists: a view onto the shared ``RepositoryStore``.
///
/// The store is the pool — every folder adopted, each with one bookmark — and
/// this is the part of it a window shows, in that window's order. Adding to it
/// joins a record the pool already has when there is one, and removing from it
/// only takes the repository out of this window: the record, its bookmark and
/// the folder access behind it stay, because they are what the user would have
/// to recreate by hand.
///
/// The one consequence is that a repository no window lists can only be got back
/// by picking its folder again. That joins the existing record, so nothing is
/// lost, but it is clumsy; a list of what was adopted before belongs in the add
/// modal.
@MainActor
@Observable
public final class WindowRepositories {
    /// In this window's order.
    public private(set) var members: [RepositoryMembership]

    /// Called after a change to ``members``, so whoever persists the window can
    /// write it down. Observation reports reads rather than writes, so nothing
    /// else would notice.
    @ObservationIgnored
    public var onChange: (() -> Void)?

    @ObservationIgnored
    private let store: RepositoryStore

    public init(store: RepositoryStore, members: [RepositoryMembership] = []) {
        self.store = store
        self.members = members
    }

    /// The repositories this window lists, resolved through the pool. One whose
    /// record has been forgotten outright is skipped rather than shown blank.
    public var repositories: [Repository] {
        members.compactMap { store[$0.repositoryID] }
    }

    /// Any record in the pool, listed here or not. For what needs a name or a
    /// path and has only an id.
    public func repository(id: UUID) -> Repository? {
        store[id]
    }

    public func contains(_ repository: Repository) -> Bool {
        members.contains { $0.repositoryID == repository.id }
    }

    public func isCollapsed(_ repository: Repository) -> Bool {
        members.first { $0.repositoryID == repository.id }?.isCollapsed ?? false
    }

    /// The repositories the sidebar shows: the ones the selector has not left
    /// out, in this window's order.
    ///
    /// Never empty while anything is listed. Hiding refuses to hide the last
    /// one, but removing can take away the only one showing, and a sidebar
    /// with workspaces and nothing on it would look like it had none.
    public var shown: [Repository] {
        let listed = repositories
        let visible = listed.filter { !isHidden($0) }
        return visible.isEmpty ? listed : visible
    }

    public func isShown(_ repository: Repository) -> Bool {
        shown.contains { $0.id == repository.id }
    }

    private func isHidden(_ repository: Repository) -> Bool {
        members.first { $0.repositoryID == repository.id }?.isHidden ?? false
    }

    // MARK: - Changing

    /// Whether a folder could be added to this window, without adding it.
    /// Everything the store refuses, and a folder this window already lists.
    ///
    /// One that only another window lists is fine: adding it joins the existing
    /// record.
    @discardableResult
    public func validate(url: URL) async throws -> GitRepositoryKind {
        let kind = try await store.validate(url: url)
        if let pooled = store.pooled(holding: url), contains(pooled) {
            throw RepositoryStoreError.alreadyOpen(url)
        }
        return kind
    }

    /// Adds a folder to the bottom of this window's sidebar, adopting it first
    /// if the pool has not got it. See ``RepositoryStore/add(url:name:)``.
    @discardableResult
    public func add(url: URL, name: String? = nil) async throws -> Repository {
        try await validate(url: url)
        let repository = try await store.add(url: url, name: name)
        members.append(RepositoryMembership(repositoryID: repository.id))
        onChange?()
        return repository
    }

    /// Takes a repository out of this window. The record stays in the pool.
    public func remove(_ repository: Repository) {
        guard contains(repository) else { return }
        members.removeAll { $0.repositoryID == repository.id }
        onChange?()
    }

    /// Folds this repository's worktrees away in this window, or shows them.
    ///
    /// Persisted, because it is the user's arrangement and they would have to
    /// redo it on every launch otherwise.
    public func setCollapsed(_ repository: Repository, _ isCollapsed: Bool) {
        guard let index = members.firstIndex(where: { $0.repositoryID == repository.id }) else { return }
        guard members[index].isCollapsed != isCollapsed else { return }
        members[index].isCollapsed = isCollapsed
        onChange?()
    }

    /// Shows this repository in the sidebar, or leaves it out. Leaving out the
    /// last one showing is refused: see ``shown``.
    ///
    /// Persisted, like folding, because it is the user's arrangement.
    public func setShown(_ repository: Repository, _ isShown: Bool) {
        guard let index = members.firstIndex(where: { $0.repositoryID == repository.id }) else { return }
        if !isShown, shown.map(\.id) == [repository.id] { return }
        // From what is on screen, not from the flags: while the fallback is
        // showing everything, the flags say everything is hidden.
        var next = Set(shown.map(\.id))
        if isShown { next.insert(repository.id) } else { next.remove(repository.id) }
        apply(shown: next)
    }

    /// Shows every repository this window lists.
    public func showAll() {
        apply(shown: Set(members.map(\.repositoryID)))
    }

    private func apply(shown ids: Set<UUID>) {
        var updated = members
        for index in updated.indices {
            updated[index].isHidden = !ids.contains(updated[index].repositoryID)
        }
        guard updated != members else { return }
        members = updated
        onChange?()
    }

    /// Puts this window's repositories in the given order. Anything not named
    /// keeps its place after the ones that are.
    public func reorder(to ordered: [Repository]) {
        let position = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0) })
        let reordered = members.enumerated().sorted { lhs, rhs in
            switch (position[lhs.element.repositoryID], position[rhs.element.repositoryID]) {
            case let (l?, r?): l < r
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): lhs.offset < rhs.offset
            }
        }.map(\.element)
        guard reordered != members else { return }
        members = reordered
        onChange?()
    }

    /// Renames a repository. The name is the pool's, so every window listing it
    /// shows the new one.
    public func rename(_ repository: Repository, to name: String) async {
        await store.rename(repository, to: name)
    }
}
