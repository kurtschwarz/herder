import Foundation
import Observation

/// The user's settings, live: what `settings.json` says, kept in step with the
/// file in both directions.
///
/// The Settings window and the file are two ways to edit this one value. A
/// change made in the window is applied at once and written ``writeDelay``
/// after the changes stop, so typing in a field does not write on every key.
/// A change made to the file, in Herder's editor or any other, is read when
/// the file's folder reports it and applied in place.
///
/// - A file that cannot be read as settings keeps the last good value, and
///   ``problem`` says what is wrong until the file is fixed. It is never
///   written over: it is somebody's edit in progress. Changes made in the
///   window meanwhile apply until the file is fixed, and are not saved.
/// - A missing file is every setting at its default. It is not made again
///   until the window changes something or ``createFileIfMissing()`` is asked.
/// - A change that reads back as the text last seen, which is what our own
///   write looks like when the folder reports it, is ignored.
///
/// App-wide: ``AgentCatalog`` and ``NamingSettings`` read and write through
/// it, and every window sees one value.
///
/// The annotation is explicit because `Core` keeps the nonisolated default.
@MainActor
@Observable
public final class UserSettingsStore {
    /// How long the window's changes have to stop before they are written.
    public static let writeDelay = Duration.milliseconds(300)

    /// The settings in force: the last good read of the file, with the
    /// window's changes on top.
    public private(set) var settings = UserSettings()

    /// Why the file could not be used, until it can. The settings in force
    /// are the last good ones meanwhile.
    public private(set) var problem: String?

    /// Told every time ``settings`` changes, for something that has to be
    /// pushed a value rather than read it: the updater.
    @ObservationIgnored public var onChange: ((UserSettings) -> Void)?

    @ObservationIgnored private let file: any SettingsFileClient
    @ObservationIgnored private let clock: any ClockClient

    /// The text the settings in force came from or went to: `.none` until the
    /// file has been looked at, `.some(nil)` for no file.
    @ObservationIgnored private var lastSeen: String??

    @ObservationIgnored private var needsWrite = false

    /// The file is there and cannot be used, so nothing may replace it.
    @ObservationIgnored private var fileIsUnusable = false
    @ObservationIgnored private var debounce: Task<Void, Never>?

    /// The tail of the writes. Each waits for the one before, so an older
    /// file can never be written over a newer one.
    @ObservationIgnored private var writing: Task<Void, Never>?
    @ObservationIgnored private var watching: Task<Void, Never>?

    public init(file: any SettingsFileClient, clock: any ClockClient) {
        self.file = file
        self.clock = clock
    }

    /// Where the file is, whether or not it exists.
    public var url: URL { file.url }

    // MARK: - Reading

    /// Reads the file.
    ///
    /// On the first launch that has no file, the settings that used to live
    /// in `state` are moved into one: the first-prompt template and the
    /// custom agents from the `agents` snapshot, the endpoint from `naming`,
    /// and the update toggle from `updater`. The file is written only if any
    /// of them differs from its default. The old fields stay on disk, unused.
    public func load(migratingFrom state: (any StateStore)? = nil, updater: (any UpdaterClient)? = nil) async {
        let text: String?
        do {
            text = try await file.read()
        } catch {
            problem = Self.describeUnreadable(error)
            fileIsUnusable = true
            return
        }

        if let state, await state.loadIfReadable(SettingsMigrationSnapshot.self, forKey: SettingsMigrationSnapshot.persistenceKey)?.migrated != true {
            if text == nil {
                await migrate(from: state, updater: updater)
                return
            }
            try? await state.save(SettingsMigrationSnapshot(), forKey: SettingsMigrationSnapshot.persistenceKey)
        }
        apply(text)
    }

    /// Reads the file again whenever its folder changes, until
    /// ``stopWatching()``.
    public func startWatching() {
        guard watching == nil else { return }
        let changes = file.changes()
        watching = Task { [weak self] in
            for await _ in changes {
                await self?.reread()
            }
        }
    }

    public func stopWatching() {
        watching?.cancel()
        watching = nil
    }

    /// What a change to the folder means: nothing, if the file holds what was
    /// last seen; otherwise the file's settings, or its problem.
    func reread() async {
        let text: String?
        do {
            text = try await file.read()
        } catch {
            problem = Self.describeUnreadable(error)
            fileIsUnusable = true
            return
        }
        guard lastSeen != .some(text) else { return }
        // The file wins over changes the window has not written yet: writing
        // them now would put back what was just replaced.
        needsWrite = false
        debounce?.cancel()
        apply(text)
    }

    private func apply(_ text: String?) {
        lastSeen = .some(text)
        guard let text else {
            set(UserSettings())
            problem = nil
            fileIsUnusable = false
            return
        }
        do {
            set(try UserSettings.decode(text))
            problem = nil
            fileIsUnusable = false
        } catch {
            problem = error.localizedDescription
            fileIsUnusable = true
        }
    }

    private func set(_ next: UserSettings) {
        guard next != settings else { return }
        settings = next
        onChange?(next)
    }

    // MARK: - Changing

    /// Applies `change` now and writes the file once changes stop: the whole
    /// file, sparse. Not while the file cannot be used, which is left for
    /// the person editing it.
    public func update(_ change: (inout UserSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        set(next)
        scheduleWrite()
    }

    /// Makes the file if there is none, for opening it in an editor: the
    /// settings in force, which with no file are the defaults, so a new file
    /// is only its `$schema`. Writes anything waiting first.
    public func createFileIfMissing() async {
        await flushWrites()
        do {
            guard try await file.read() == nil else { return }
        } catch {
            // There is something there, unreadable: not ours to replace.
            return
        }
        needsWrite = true
        await flushWrites()
    }

    /// Writes now anything waiting on the delay, and waits for every write.
    public func flushWrites() async {
        writeNow()
        await writing?.value
    }

    private func scheduleWrite() {
        needsWrite = true
        debounce?.cancel()
        debounce = Task { [clock] in
            do {
                try await clock.sleep(for: Self.writeDelay)
            } catch {
                return
            }
            self.writeNow()
        }
    }

    private func writeNow() {
        debounce?.cancel()
        debounce = nil
        guard needsWrite, !fileIsUnusable, let text = try? settings.encoded() else { return }
        needsWrite = false
        lastSeen = .some(text)
        problem = nil
        let previous = writing
        writing = Task { [file] in
            await previous?.value
            do {
                try await file.write(text)
            } catch {
                self.problem = "Couldn\u{2019}t save settings.json: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Migrating

    private func migrate(from state: any StateStore, updater: (any UpdaterClient)?) async {
        var migrated = UserSettings()
        if let agents = await state.loadIfReadable(AgentsSnapshot.self, forKey: AgentsSnapshot.persistenceKey) {
            migrated.firstPromptTemplate = agents.firstPromptTemplate ?? ""
            var taken: Set<Agent.ID> = []
            for var agent in agents.custom {
                agent = agent.withID(Self.migratedID(of: agent, taken: taken))
                taken.insert(agent.id)
                migrated.customAgents.append(agent)
            }
        }
        if let naming = await state.loadIfReadable(NamingSnapshot.self, forKey: NamingSnapshot.persistenceKey) {
            migrated.anthropicEndpoint = naming.endpoint
        }
        if let updater {
            migrated.checkForUpdatesAutomatically = updater.automaticallyChecksForUpdates
        }

        lastSeen = .some(nil)
        set(migrated)
        if migrated != UserSettings() {
            needsWrite = true
            await flushWrites()
            // Tried again next launch rather than marked done with nothing
            // written.
            guard problem == nil else { return }
        }
        try? await state.save(SettingsMigrationSnapshot(), forKey: SettingsMigrationSnapshot.persistenceKey)
    }

    /// The id an agent keeps in the file. Ids minted before the file were
    /// `custom-` and an uppercase UUID, so they are lowercased to fit the
    /// file's rule; ``AgentCatalog/agent(_:)`` still finds them by the old
    /// spelling, which is what the last-used agent and saved tabs hold.
    private static func migratedID(of agent: Agent, taken: Set<Agent.ID>) -> Agent.ID {
        let lowered = agent.id.lowercased()
        guard UserSettings.isValidAgentID(lowered), !taken.contains(lowered),
              !Agent.presets.contains(where: { $0.id == lowered })
        else { return UserSettings.mintAgentID(for: agent.name, taken: taken) }
        return lowered
    }

    private static func describeUnreadable(_ error: any Error) -> String {
        if case FileClientError.notUTF8 = error { return "It isn\u{2019}t UTF-8 text." }
        return "Couldn\u{2019}t read settings.json: \(error.localizedDescription)"
    }
}
