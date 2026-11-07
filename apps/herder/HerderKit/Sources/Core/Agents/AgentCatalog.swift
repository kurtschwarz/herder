import Foundation
import Observation

/// The agents a session can be started with: the presets, the ones the user
/// added, and which was used last.
///
/// App-wide, not per window: Settings edits it, every window's agent panel and
/// sidebar start sessions from it, and "the one used last" means the last one
/// anywhere.
///
/// The annotation is explicit because `Core` keeps the nonisolated default.
@MainActor
@Observable
public final class AgentCatalog {
    private let state: any StateStore

    /// The agents the user added, in the order they were added.
    public private(set) var custom: [Agent] = []

    private var lastUsedID: Agent.ID?

    /// The tail of the saves. Each waits for the one before, so an older list
    /// can never be written over a newer one.
    @ObservationIgnored
    private var saving: Task<Void, Never>?

    public init(state: any StateStore) {
        self.state = state
    }

    // MARK: - Reading

    /// Everything a menu offers, presets first.
    public var agents: [Agent] {
        Agent.presets + custom
    }

    /// What starts when nobody says which: the agent used last, or the first
    /// preset before anything has been.
    public var lastUsed: Agent {
        lastUsedID.flatMap(agent) ?? Agent.presets[0]
    }

    public func agent(_ id: Agent.ID) -> Agent? {
        agents.first { $0.id == id }
    }

    // MARK: - Loading

    /// Reads what was saved. Unreadable state is no agents of the user's own,
    /// which loses less than refusing to start.
    public func load() async {
        guard let snapshot = await state.loadIfReadable(AgentsSnapshot.self, forKey: AgentsSnapshot.persistenceKey)
        else { return }
        custom = snapshot.custom
        lastUsedID = snapshot.lastUsed
    }

    // MARK: - Changing

    public func markUsed(_ agent: Agent) {
        guard lastUsedID != agent.id else { return }
        lastUsedID = agent.id
        save()
    }

    /// Adds an agent with nothing filled in, for Settings to fill in.
    @discardableResult
    public func add() -> Agent {
        let agent = Agent(id: "custom-\(UUID().uuidString)", name: "", command: "")
        custom.append(agent)
        save()
        return agent
    }

    /// Takes a changed name or command. The presets cannot be changed: they
    /// are code.
    public func update(_ agent: Agent) {
        guard let index = custom.firstIndex(where: { $0.id == agent.id }), custom[index] != agent else { return }
        custom[index] = agent
        save()
    }

    public func remove(_ id: Agent.ID) {
        guard custom.contains(where: { $0.id == id }) else { return }
        custom.removeAll { $0.id == id }
        if lastUsedID == id { lastUsedID = nil }
        save()
    }

    // MARK: - Saving

    /// Writes the list at once, not after a pause: it changes only when
    /// somebody edits it or starts a session, and the snapshot is a few lines.
    private func save() {
        let snapshot = AgentsSnapshot(custom: custom, lastUsed: lastUsedID)
        let previous = saving
        saving = Task { [state] in
            await previous?.value
            try? await state.save(snapshot, forKey: AgentsSnapshot.persistenceKey)
        }
    }

    /// Waits for every save asked for so far.
    public func flushSaves() async {
        await saving?.value
    }
}
