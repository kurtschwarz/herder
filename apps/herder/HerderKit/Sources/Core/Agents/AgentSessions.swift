import Foundation
import Observation

/// Every agent session there has been, per repository: the records, without
/// what their tabs are doing. What the sidebar's history lists, and what
/// resuming one reads.
///
/// App-wide, and the one writer of each repository's history file, because
/// two windows can list one repository. What each window has open, and what
/// it is doing, is that window's: ``WindowAgentSessions``. That changes every
/// second while an agent works, and kept here it would redraw every window's
/// sidebar for one window's agent. This changes only when a record does.
///
/// A session is written down once its agent is running and the person has
/// said something to it: a tab that never started, or was opened and left
/// alone, is not history. It ends when the person closes the tab or the program quits by itself with
/// status 0 — nothing else: a tab whose program failed stays up, and one
/// remembered across a quit, or in a window that closed, is only paused. A
/// session whose tab was lost without being closed, by a crash, is ended when
/// its worktree is next restored: see ``reconcile(_:claimed:)``.
///
/// The annotation is explicit because `Core` keeps the nonisolated default.
@MainActor
@Observable
public final class AgentSessions {
    /// What a panel says about one of its open tabs. See
    /// ``WindowAgentSessions/publish(_:focused:at:)``.
    public struct Report: Sendable, Equatable {
        public var id: UUID
        public var worktree: WorkspaceID
        public var agentID: Agent.ID
        public var agentName: String

        /// The person's name for it, or the program's: a title worth keeping.
        /// `nil` when it has neither, as a paused tab does.
        public var title: String?

        /// The person's name for it alone, without the program's.
        public var name: String?

        /// What to call it when nothing better is known: the agent's name,
        /// and which of its sessions this is.
        public var fallbackTitle: String

        public var sessionID: String?
        public var state: AgentSession.State
        public var lastActivity: Date

        public init(
            id: UUID,
            worktree: WorkspaceID,
            agentID: Agent.ID,
            agentName: String,
            title: String?,
            name: String? = nil,
            fallbackTitle: String,
            sessionID: String?,
            state: AgentSession.State,
            lastActivity: Date
        ) {
            self.id = id
            self.worktree = worktree
            self.agentID = agentID
            self.agentName = agentName
            self.title = title
            self.name = name
            self.fallbackTitle = fallbackTitle
            self.sessionID = sessionID
            self.state = state
            self.lastActivity = lastActivity
        }
    }

    /// How long after the last change to a repository's history a save waits.
    static let saveDebounce = Duration.milliseconds(400)

    /// How much later than the last write a session is written down as seen
    /// again. Coarse on purpose: this is what an unseen end is dated by, and
    /// a minute is close enough for that.
    static let seenGranularity: TimeInterval = 60

    private let git: any GitClient
    private let state: any StateStore
    private let clock: any ClockClient

    /// When this launch began. A session seen since was seen by this launch
    /// and is not an orphan of an earlier one, whatever its tab says.
    private let launchedAt: Date

    /// Every session written down, by id. None has a ``AgentSession/live``
    /// part: that is the window's.
    public private(set) var sessions: [UUID: AgentSession] = [:]

    /// The repository each session belongs to, which is also which file it
    /// is written to.
    @ObservationIgnored private var repositoryOfSession: [UUID: PathKey] = [:]

    /// The sessions each window has a tab open for, so a crash's leftovers can
    /// be told from a tab another window has. Not observed: nothing draws it.
    @ObservationIgnored private var openByWindow: [UUID: Set<UUID>] = [:]
    @ObservationIgnored private var repositoryOfWorkspace: [WorkspaceID: PathKey] = [:]
    @ObservationIgnored private var loaded: Set<PathKey> = []
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

    public func session(_ id: UUID) -> AgentSession? {
        sessions[id]
    }

    /// The sessions written down in `repository`, open or ended, first
    /// started first.
    public func recorded(in repository: PathKey) -> [AgentSession] {
        sessions.values
            .filter { repositoryOfSession[$0.id] == repository }
            .sorted { $0.startedAt < $1.startedAt }
    }

    /// The sessions that have ended in `repository`, latest end first.
    public func ended(in repository: PathKey) -> [AgentSession] {
        recorded(in: repository)
            .filter(\.isEnded)
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
    }

    /// Reads `repository`'s file, once. The sidebar asks for it when it lists
    /// the repository.
    public func load(_ repository: PathKey) async {
        if loaded.contains(repository) { return }
        if let task = loading[repository] {
            await task.value
            return
        }
        let task = Task {
            let stored = await state.loadIfReadable(
                SessionHistorySnapshot.self, forKey: SessionHistorySnapshot.persistenceKey(for: repository)
            )
            var next = sessions
            for record in stored?.records ?? [] {
                // Written down since this launch began, so newer than the file.
                guard repositoryOfSession[record.id] == nil else { continue }
                next[record.id] = record
                repositoryOfSession[record.id] = repository
            }
            loaded.insert(repository)
            if next != sessions { sessions = next }
        }
        loading[repository] = task
        await task.value
        loading[repository] = nil
    }

    // MARK: - Open tabs

    /// Takes what `window`'s tabs say about the sessions written down: what
    /// each is called now, and by the person alone, its agent's id once
    /// found, and that it is still running. Changes a record only when one of
    /// those changed, and its last-seen time no oftener than
    /// ``seenGranularity``, so a panel reporting every second costs nothing
    /// here. Also notes which sessions
    /// the window has open, for ``reconcile(_:claimed:)``.
    public func note(_ reports: [Report], window: UUID, at now: Date = .now) {
        openByWindow[window] = reports.isEmpty ? nil : Set(reports.map(\.id))

        var next = sessions
        var changed: Set<PathKey> = []
        for report in reports {
            guard let key = repositoryOfSession[report.id], var session = next[report.id] else { continue }
            let before = session
            if let title = report.title { session.title = title }
            session.name = report.name
            if let sessionID = report.sessionID { session.sessionID = sessionID }
            if report.state.isRunning, now.timeIntervalSince(session.lastSeenAt) >= Self.seenGranularity {
                session.lastSeenAt = now
            }
            guard session != before else { continue }
            next[report.id] = session
            changed.insert(key)
        }
        guard !changed.isEmpty else { return }
        sessions = next
        for key in changed { scheduleSave(key) }
    }

    // MARK: - Writing down

    /// Writes down a session whose agent has just run, in `session.worktree`.
    /// Does nothing for one already written down, here or in its file: a
    /// resumed session is the one it was.
    public func begin(_ session: AgentSession) async {
        let key = await repositoryKey(of: session.worktree)
        await load(key)
        guard repositoryOfSession[session.id] == nil else { return }
        repositoryOfSession[session.id] = key
        sessions[session.id] = session.record
        scheduleSave(key)
    }

    /// Ends a session: its tab was closed, or its program quit.
    public func end(_ id: UUID, because reason: AgentSession.EndReason, at date: Date = .now) {
        update(id) { session in
            guard !session.isEnded else { return false }
            session.endedAt = date
            session.endReason = reason
            session.lastSeenAt = max(session.lastSeenAt, date)
            return true
        }
    }

    /// Makes an ended session open again, keeping when it first started.
    public func reopen(_ id: UUID, at date: Date = .now) {
        update(id) { session in
            guard session.isEnded else { return false }
            session.endedAt = nil
            session.endReason = nil
            session.lastSeenAt = date
            return true
        }
    }

    /// Names an ended session, which is what it is listed as, and what its
    /// tab is called if it is resumed. A blank name changes nothing. One
    /// still open is named in its tab instead, which would undo this.
    public func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { session in
            guard session.isEnded, session.name != trimmed || session.title != trimmed else { return false }
            session.name = trimmed
            session.title = trimmed
            return true
        }
    }

    /// Takes an ended session out of the history, and its file. What was said
    /// in it stays with its agent. One still open is left alone: its tab
    /// would only write it down again.
    public func delete(_ id: UUID) {
        guard let key = repositoryOfSession[id], sessions[id]?.isEnded == true else { return }
        sessions[id] = nil
        repositoryOfSession[id] = nil
        scheduleSave(key)
    }

    /// Ends the open sessions in `workspace` that no tab is left for: Herder
    /// stopped before it wrote down that they were closed. Each is dated by
    /// the last time it was seen. Sessions seen since this launch began, or
    /// with a tab open in any window, are left alone.
    public func reconcile(_ workspace: WorkspaceID, claimed: Set<UUID>) async {
        let key = await repositoryKey(of: workspace)
        await load(key)
        let open = openByWindow.values.reduce(into: claimed) { $0.formUnion($1) }
        var next = sessions
        for session in recorded(in: key)
        where session.worktree == workspace && !session.isEnded
            && !open.contains(session.id) && session.lastSeenAt < launchedAt {
            next[session.id]?.endedAt = session.lastSeenAt
            next[session.id]?.endReason = .unknown
        }
        guard next != sessions else { return }
        sessions = next
        scheduleSave(key)
    }

    private func update(_ id: UUID, _ change: (inout AgentSession) -> Bool) {
        guard let key = repositoryOfSession[id], var session = sessions[id], change(&session) else { return }
        sessions[id] = session
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
        let snapshot = SessionHistorySnapshot(records: recorded(in: key))
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
