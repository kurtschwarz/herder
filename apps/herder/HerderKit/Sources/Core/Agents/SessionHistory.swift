import Foundation
import Observation

/// Every agent session there has been, per repository: what the sidebar lists
/// under "history", and what resuming one reads.
///
/// App-wide, because two windows can list one repository and each would
/// otherwise write its own copy of the file. This is the one writer: every
/// window's panel reports into it, and it saves each repository's file after
/// the changes to it settle.
///
/// A record is made when a session's terminal UI first starts and lives on
/// after the tab is gone. It ends when the person closes the tab or the
/// program quits by itself with status 0 — nothing else: a tab whose program
/// failed stays up, and one remembered across a quit is only paused. A record
/// whose tab was lost without being closed, by a crash, is ended when its
/// worktree is next restored: see ``reconcile(_:claimed:)``.
///
/// The annotation is explicit because `Core` keeps the nonisolated default.
@MainActor
@Observable
public final class SessionHistory {
    /// How long after the last change to a repository's history a save waits.
    static let saveDebounce = Duration.milliseconds(400)

    /// How much later than the last write a session is written down as seen
    /// again. Coarse on purpose: this is what an unseen end is dated by, and
    /// a minute is close enough for that.
    static let seenGranularity: TimeInterval = 60

    private let git: any GitClient
    private let state: any StateStore
    private let clock: any ClockClient

    /// When this launch began. A record seen since was seen by this launch and
    /// is not an orphan of an earlier one, whatever its tab says.
    private let launchedAt: Date

    /// The history of each repository that has been read, newest start last.
    public private(set) var repositories: [PathKey: [SessionHistoryRecord]] = [:]

    @ObservationIgnored private var repositoryOfRecord: [UUID: PathKey] = [:]
    @ObservationIgnored private var repositoryOfWorkspace: [WorkspaceID: PathKey] = [:]
    @ObservationIgnored private var loading: [PathKey: Task<Void, Never>] = [:]
    @ObservationIgnored private var saves: [PathKey: Task<Void, Never>] = [:]

    public init(git: any GitClient, state: any StateStore, clock: any ClockClient, launchedAt: Date = .now) {
        self.git = git
        self.state = state
        self.clock = clock
        self.launchedAt = launchedAt
    }

    // MARK: - Which repository

    /// The key a repository's history is kept under: its main working tree.
    /// Without one — a bare repository — the first worktree by path, which is
    /// the best a layout with nothing to name it allows.
    public static func repositoryKey(for worktrees: [GitWorktree], fallback: PathKey) -> PathKey {
        if let main = worktrees.first(where: \.isMainWorkingTree) { return PathKey(main.path) }
        return worktrees.map { PathKey($0.path) }.min() ?? fallback
    }

    /// The repository `workspace` is a worktree of, from what git says about
    /// it. A folder git knows nothing about is a repository of its own.
    func repositoryKey(of workspace: WorkspaceID) async -> PathKey {
        if let known = repositoryOfWorkspace[workspace] { return known }
        let worktrees = (try? await git.worktrees(at: workspace.url)) ?? []
        let key = Self.repositoryKey(for: worktrees, fallback: workspace.root)
        repositoryOfWorkspace[workspace] = key
        return key
    }

    // MARK: - Reading

    /// The sessions that have ended in `repository`, latest end first.
    public func ended(in repository: PathKey) -> [SessionHistoryRecord] {
        (repositories[repository] ?? [])
            .filter(\.isEnded)
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
    }

    public func record(_ id: UUID) -> SessionHistoryRecord? {
        guard let key = repositoryOfRecord[id] else { return nil }
        return repositories[key]?.first { $0.id == id }
    }

    /// Reads `repository`'s file, once. The sidebar asks for it when it lists
    /// the repository.
    public func load(_ repository: PathKey) async {
        if repositories[repository] != nil { return }
        if let task = loading[repository] {
            await task.value
            return
        }
        let task = Task {
            let stored = await state.loadIfReadable(
                SessionHistorySnapshot.self, forKey: SessionHistorySnapshot.persistenceKey(for: repository)
            )
            // Whatever was recorded while this was reading is newer.
            let recorded = repositories[repository] ?? []
            let known = Set(recorded.map(\.id))
            let merged = (stored?.records ?? []).filter { !known.contains($0.id) } + recorded
            for record in merged { repositoryOfRecord[record.id] = repository }
            repositories[repository] = merged
        }
        loading[repository] = task
        await task.value
        loading[repository] = nil
    }

    // MARK: - Changing

    /// Starts a record for a session whose terminal UI has just started in
    /// `record.worktree`. Does nothing for one already recorded.
    public func begin(_ record: SessionHistoryRecord) async {
        let key = await repositoryKey(of: record.worktree)
        await load(key)
        guard repositoryOfRecord[record.id] == nil else { return }
        repositoryOfRecord[record.id] = key
        repositories[key, default: []].append(record)
        scheduleSave(key)
    }

    /// Notes what a running session is called now and that it is still
    /// there. Writes only what changed, and the time no oftener than
    /// ``seenGranularity``, so calling it every second costs nothing.
    public func touch(_ id: UUID, title: String, sessionID: String?, at now: Date = .now) {
        update(id) { record in
            var changed = false
            if record.title != title { record.title = title; changed = true }
            if let sessionID, record.sessionID != sessionID { record.sessionID = sessionID; changed = true }
            if now.timeIntervalSince(record.lastSeenAt) >= Self.seenGranularity {
                record.lastSeenAt = now
                changed = true
            }
            return changed
        }
    }

    /// Ends a session: its tab was closed, or its program quit.
    public func end(_ id: UUID, because reason: SessionHistoryRecord.EndReason, at date: Date = .now) {
        update(id) { record in
            guard !record.isEnded else { return false }
            record.endedAt = date
            record.endReason = reason
            record.lastSeenAt = max(record.lastSeenAt, date)
            return true
        }
    }

    /// Makes an ended session open again, keeping when it first started.
    public func reopen(_ id: UUID, at date: Date = .now) {
        update(id) { record in
            guard record.isEnded else { return false }
            record.endedAt = nil
            record.endReason = nil
            record.lastSeenAt = date
            return true
        }
    }

    /// Ends the open sessions in `workspace` that no tab is left for: Herder
    /// stopped before it wrote down that they were closed. Each is dated by
    /// the last time it was seen. Sessions seen since this launch began are
    /// left alone.
    public func reconcile(_ workspace: WorkspaceID, claimed: Set<UUID>) async {
        let key = await repositoryKey(of: workspace)
        await load(key)
        var changed = false
        for index in repositories[key]?.indices ?? 0..<0 {
            guard let record = repositories[key]?[index],
                  record.worktree == workspace, !record.isEnded,
                  !claimed.contains(record.id), record.lastSeenAt < launchedAt
            else { continue }
            repositories[key]?[index].endedAt = record.lastSeenAt
            repositories[key]?[index].endReason = .unknown
            changed = true
        }
        if changed { scheduleSave(key) }
    }

    private func update(_ id: UUID, _ change: (inout SessionHistoryRecord) -> Bool) {
        guard let key = repositoryOfRecord[id],
              let index = repositories[key]?.firstIndex(where: { $0.id == id })
        else { return }
        var record = repositories[key]![index]
        guard change(&record) else { return }
        repositories[key]![index] = record
        scheduleSave(key)
    }

    // MARK: - Saving

    private func scheduleSave(_ key: PathKey) {
        saves[key]?.cancel()
        saves[key] = Task { [weak self, clock] in
            try? await clock.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            await self?.save(key)
        }
    }

    private func save(_ key: PathKey) async {
        saves[key] = nil
        let snapshot = SessionHistorySnapshot(records: repositories[key] ?? [])
        // The next change tries again; losing a title is not worth failing
        // anything over.
        try? await state.save(snapshot, forKey: SessionHistorySnapshot.persistenceKey(for: key))
    }

    /// Writes everything waiting now.
    public func flushSaves() async {
        for key in Array(saves.keys) {
            saves[key]?.cancel()
            await save(key)
        }
    }
}
