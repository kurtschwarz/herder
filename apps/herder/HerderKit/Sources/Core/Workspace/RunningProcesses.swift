import Foundation
import Observation

/// Every tab in the app that has a process running, in any window: the agent
/// sessions and the terminals.
///
/// App-wide, because the Task Manager is one window and has to find the tabs
/// of all of them, and a window's models are out of its reach. Each window's
/// agent panel and terminal panel write it and the Task Manager reads it,
/// which is how features that cannot see each other share what is running.
///
/// An entry is made when a tab's process starts. A terminal's goes when the
/// process does; an agent's stays, marked ended, until its tab is closed, so
/// the Task Manager can say it is done and not simply lose it.
///
/// The annotation is explicit because `Core` keeps the nonisolated default.
@MainActor
@Observable
public final class RunningProcesses {
    public struct Entry: Identifiable {
        /// The tab's: the session's id for an agent, the shell tab's for a
        /// terminal.
        public let id: UUID
        public var kind: ProcessOwner.Kind
        public var window: UUID
        public var workspace: WorkspaceID

        /// The process the tab started, or `nil` once it has ended.
        public var pid: Int32?

        /// Read each time the Task Manager refreshes, because a title changes
        /// while the tab lives.
        public var title: @MainActor () -> String
        public var branch: @MainActor () -> String?

        /// What the agent is doing, read the way the sidebar reads it. `nil`
        /// for a terminal.
        public var state: @MainActor () -> AgentSession.State?

        /// Brings the tab forward in its window, and raises the window.
        public var show: @MainActor () -> Void

        public init(
            id: UUID,
            kind: ProcessOwner.Kind,
            window: UUID,
            workspace: WorkspaceID,
            pid: Int32?,
            title: @escaping @MainActor () -> String,
            branch: @escaping @MainActor () -> String? = { nil },
            state: @escaping @MainActor () -> AgentSession.State? = { nil },
            show: @escaping @MainActor () -> Void
        ) {
            self.id = id
            self.kind = kind
            self.window = window
            self.workspace = workspace
            self.pid = pid
            self.title = title
            self.branch = branch
            self.state = state
            self.show = show
        }
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    /// Adds an entry, or replaces the one with its id: an agent started again
    /// in its tab has a new process and the same place in the list.
    public func register(_ entry: Entry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    /// The tab's process has ended, and the tab is still open.
    public func processEnded(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].pid != nil else { return }
        entries[index].pid = nil
    }

    public func unregister(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    public func entry(_ id: UUID) -> Entry? {
        entries.first { $0.id == id }
    }

    /// Each entry as a value, with its closures read now.
    public var owners: [ProcessOwner] {
        entries.map { entry in
            ProcessOwner(
                id: entry.id,
                kind: entry.kind,
                window: entry.window,
                worktree: entry.workspace,
                branch: entry.branch(),
                title: entry.title(),
                pid: entry.pid,
                state: entry.state()
            )
        }
    }
}
