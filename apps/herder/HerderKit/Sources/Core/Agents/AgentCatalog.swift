import Foundation
import Observation

/// The agents a session can be started with: the presets, the ones the user
/// added, and which was used last.
///
/// App-wide, not per window: Settings edits it, every window's agent panel and
/// sidebar start sessions from it, and "the one used last" means the last one
/// anywhere.
///
/// The user's agents and the first-prompt template are user settings, read
/// and written through ``UserSettingsStore``. Which agent was used last is the
/// app's own state, and stays in the `agents` snapshot.
///
/// The annotation is explicit because `Core` keeps the nonisolated default.
@MainActor
@Observable
public final class AgentCatalog {
    private let state: any StateStore
    private let store: UserSettingsStore

    private var lastUsedID: Agent.ID?

    /// The snapshot as it was read, so writing the agent used last keeps the
    /// fields builds before `settings.json` wrote. Nothing reads them now.
    @ObservationIgnored
    private var snapshot = AgentsSnapshot()

    /// The tail of the saves. Each waits for the one before, so an older list
    /// can never be written over a newer one.
    @ObservationIgnored
    private var saving: Task<Void, Never>?

    public init(state: any StateStore, settings: UserSettingsStore) {
        self.state = state
        self.store = settings
    }

    // MARK: - Reading

    /// The agents the user added, in the order they were added.
    public var custom: [Agent] {
        store.settings.customAgents
    }

    /// What every New order's text is put in before the agent is told it. See
    /// ``FirstPromptTemplate``. Empty leaves the text as typed.
    public var firstPromptTemplate: String {
        store.settings.firstPromptTemplate
    }

    /// Everything a menu offers, presets first.
    public var agents: [Agent] {
        Agent.presets + custom
    }

    /// What starts when nobody says which: the agent used last, or the first
    /// preset before anything has been.
    public var lastUsed: Agent {
        lastUsedID.flatMap(agent) ?? Agent.presets[0]
    }

    /// The agent with `id`. An id minted before `settings.json` was `custom-`
    /// and an uppercase UUID, and the file holds it lowercased, so one that
    /// matches nothing exactly is matched ignoring case: that is what a saved
    /// tab or a session in the history still names.
    public func agent(_ id: Agent.ID) -> Agent? {
        agents.first { $0.id == id } ?? agents.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
    }

    // MARK: - Loading

    /// Reads which agent was used last. Unreadable state is none, which loses
    /// less than refusing to start.
    public func load() async {
        guard let snapshot = await state.loadIfReadable(AgentsSnapshot.self, forKey: AgentsSnapshot.persistenceKey)
        else { return }
        self.snapshot = snapshot
        lastUsedID = snapshot.lastUsed
    }

    // MARK: - Changing

    public func markUsed(_ agent: Agent) {
        guard lastUsedID.flatMap(self.agent)?.id != agent.id else { return }
        lastUsedID = agent.id
        save()
    }

    /// Adds an agent for Settings to fill in, called `name`, with an id made
    /// from it. The id stays when the agent is renamed: the agent used last,
    /// saved tabs and the history all name it.
    @discardableResult
    public func add(named name: String = "New agent") -> Agent {
        let agent = Agent(id: UserSettings.mintAgentID(for: name, taken: custom.map(\.id)), name: name, command: "")
        store.update { $0.customAgents.append(agent) }
        return agent
    }

    /// Takes a changed name or command. The presets cannot be changed: they
    /// are code.
    public func update(_ agent: Agent) {
        guard let index = custom.firstIndex(where: { $0.id == agent.id }), custom[index] != agent else { return }
        store.update { $0.customAgents[index] = agent }
    }

    public func setFirstPromptTemplate(_ template: String) {
        store.update { $0.firstPromptTemplate = template }
    }

    public func remove(_ id: Agent.ID) {
        guard custom.contains(where: { $0.id == id }) else { return }
        store.update { $0.customAgents.removeAll { $0.id == id } }
        if lastUsedID != nil, lastUsedID.flatMap(agent) == nil {
            lastUsedID = nil
            save()
        }
    }

    // MARK: - Saving

    /// Writes the agent used last at once, not after a pause: it changes only
    /// when somebody starts a session, and the snapshot is a few lines.
    private func save() {
        snapshot.lastUsed = lastUsedID
        let snapshot = snapshot
        let previous = saving
        saving = Task { [state] in
            await previous?.value
            try? await state.save(snapshot, forKey: AgentsSnapshot.persistenceKey)
        }
    }

    /// Waits for every save asked for so far, of this and of the settings.
    public func flushSaves() async {
        await saving?.value
        await store.flushWrites()
    }
}
