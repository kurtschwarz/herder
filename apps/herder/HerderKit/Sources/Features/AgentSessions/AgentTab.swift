import Core
import Foundation
import Observation
import TerminalUI

/// One agent session's tab: an agent's terminal UI, running in a terminal of
/// its own.
@Observable
final class AgentTab: Identifiable {
    enum Phase: Equatable {
        /// Remembered from before, and not yet picked up again.
        case waiting
        case starting
        case running
        /// The terminal UI went by itself, with this status.
        case exited(Int32)
        /// It could not be started, and why.
        case failed(String)
    }

    /// Names the tab, and the agent's session too where the agent can be told
    /// its id: see ``Agent/sessionToken``. Kept across launches, so a resumed
    /// tab names the same session it started.
    let id: UUID

    /// What runs in it, as it was when the tab was opened: editing the agent
    /// in Settings afterwards changes the next session, not this one.
    let agent: Agent

    /// Which of this agent's sessions in its workspace it is, in the order
    /// they were opened. The terminal UI names its own sessions, and says
    /// nothing outside.
    let number: Int

    /// A name the person gave it, which replaces the agent's until it is
    /// cleared. Kept across launches, like the tab.
    private(set) var customName: String?

    /// The longest a name may be. About what a tab can show.
    static let maxNameLength = 40

    /// Names the tab. Blank goes back to the agent's name.
    func rename(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        customName = trimmed.isEmpty ? nil : String(trimmed.prefix(Self.maxNameLength))
    }

    /// Kept at the front of the bar, and with no close button, so it is not
    /// closed by a stray click. Kept across launches, like the tab.
    private(set) var isPinned: Bool

    func setPinned(_ pinned: Bool) { isPinned = pinned }

    private(set) var phase: Phase

    /// Whether its agent has been started before, here or before a relaunch:
    /// from then on, starting it again means resuming it.
    private(set) var hasStarted: Bool

    /// When its agent was first started, which is how a looked-up session is
    /// told apart from older ones.
    private(set) var startedAt: Date?

    /// The id the agent gave the session, for an agent that names its own.
    /// `nil` until a lookup finds it. See ``Agent/sessionLookup``.
    private(set) var sessionID: String?

    /// What the session is called in a command: the agent's own id once it is
    /// known, and otherwise the one Herder minted.
    var sessionName: String { sessionID ?? id.uuidString.lowercased() }

    /// Whether resuming needs the agent's own id and it is not known: such a
    /// session can only be started afresh.
    var isMissingSessionID: Bool { agent.looksUpSessions && sessionID == nil }

    func setSessionID(_ id: String) { sessionID = id }

    /// What the terminal UI draws on. Replaced by each attach, so a view keyed
    /// on ``generation`` starts over with it.
    private(set) var screen: TerminalScreen?
    private(set) var generation = 0

    /// When it last wrote anything, or was opened.
    private(set) var lastActivity = Date()

    /// Whether the last sample saw output of any kind, typed or not.
    @ObservationIgnored private var wroteLastSample = false
    @ObservationIgnored private var seenOutput = 0

    /// Whether the person has said anything to its agent since this launch
    /// opened or restored the tab: pressed Return in it. A tab opened and
    /// left alone is no conversation, and not worth a place in the history.
    private(set) var hasConversed = false

    /// Told when the process exits, with how.
    @ObservationIgnored var onExit: ((AgentTab, Int32) -> Void)?

    /// Told the first time the person says something to its agent.
    @ObservationIgnored var onConverse: ((AgentTab) -> Void)?

    @ObservationIgnored private var process: (any PTYSession)?
    @ObservationIgnored private var watching: Task<Void, Never>?

    /// A tab for a new session, or, with `restored`, one remembered from
    /// before, which waits to be shown before it resumes.
    init(
        id: UUID = UUID(),
        agent: Agent,
        number: Int,
        name: String? = nil,
        pinned: Bool = false,
        restored: Bool = false,
        sessionID: String? = nil,
        startedAt: Date? = nil
    ) {
        self.id = id
        self.agent = agent
        self.number = number
        self.customName = name
        self.isPinned = pinned
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.hasStarted = restored
        self.phase = restored ? .waiting : .starting
    }

    deinit {
        watching?.cancel()
    }

    /// Starts the terminal UI, replacing a stopped one.
    func attach(using pty: any PTYClient, spec: PTYSpec) async {
        phase = .starting
        terminate()

        do {
            let session = try await pty.spawn(spec)
            process = session
            let screen = TerminalScreen(session: session, size: spec.size)
            screen.onSubmit = { [weak self] in self?.converse() }
            self.screen = screen
            hasStarted = true
            if startedAt == nil { startedAt = Date() }
            wroteLastSample = false
            seenOutput = 0
            lastActivity = Date()
            generation += 1
            phase = .running
            watching = Task { [weak self] in
                let code = await session.waitForExit()
                // Hung up on by a later attach, which is not an exit.
                guard !Task.isCancelled else { return }
                self?.didExit(code)
            }
        } catch {
            let reason = switch error {
            case .openFailed(let code): "The system would not make a terminal (error \(code))."
            case .spawnFailed(let code): "Couldn\u{2019}t start \(spec.executable): \(String(cString: strerror(code)))."
            }
            phase = .failed(reason)
        }
    }

    // MARK: What it seems to be doing

    /// Looks at what the terminal did since the last look. Run about once a
    /// second. Says whether it just went quiet after writing anything, which
    /// is when a turn has most likely ended.
    @discardableResult
    func sample(now: Date) -> Bool {
        guard let screen else { return false }
        let output = screen.outputCount
        let wrote = output != seenOutput
        seenOutput = output
        if wrote { lastActivity = now }
        let wentQuiet = wroteLastSample && !wrote
        wroteLastSample = wrote
        return wentQuiet
    }

    /// While it runs, only what the program says it is doing (OSC 7501):
    /// one that says nothing is idle, whatever it writes.
    var state: AgentSession.State {
        switch phase {
        case .waiting: return .paused
        case .starting: return .starting
        case .failed: return .failed
        case .exited(let code): return .exited(code)
        case .running:
            let reported = screen?.programStatuses ?? []
            if let blocked = reported.last(where: { $0.state == .blocked }) {
                return .needsInput(blocked.message.isEmpty ? nil : blocked.message)
            }
            return reported.contains { $0.state == .working } ? .working : .idle
        }
    }

    /// What the program called itself, without the spinner or mark many put
    /// in front of it. `nil` until it says something with a word in it.
    var programTitle: String? {
        guard let title = screen?.title else { return nil }
        let trimmed = title.drop { !$0.isLetter && !$0.isNumber }
            .trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func converse() {
        guard !hasConversed else { return }
        hasConversed = true
        onConverse?(self)
    }

    private func didExit(_ code: Int32) {
        guard phase == .running else { return }
        phase = .exited(code)
        onExit?(self, code)
    }

    /// Hangs up on the terminal UI. The exit that follows is not reported:
    /// whoever hung up knows.
    func terminate() {
        watching?.cancel()
        watching = nil
        process?.terminate()
        process = nil
    }

    /// For the app quitting: see ``PTYSession/terminateNow()``.
    func terminateNow() {
        watching?.cancel()
        watching = nil
        process?.terminateNow()
        process = nil
    }
}
