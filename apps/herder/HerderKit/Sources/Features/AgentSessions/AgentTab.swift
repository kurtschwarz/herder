import Core
import Foundation
import Observation
import TerminalUI

/// One agent session's tab: an agent's terminal UI, running in a terminal of
/// its own.
@Observable
final class AgentTab: Identifiable {
    enum Phase: Equatable {
        case starting
        case running
        /// The terminal UI went by itself, with this status.
        case exited(Int32)
        /// It could not be started, and why.
        case failed(String)
    }

    let id = UUID()

    /// What runs in it, as it was when the tab was opened: editing the agent
    /// in Settings afterwards changes the next session, not this one.
    let agent: Agent

    /// Which of this agent's sessions in its workspace it is, in the order
    /// they were opened. The terminal UI names its own sessions, and says
    /// nothing outside.
    let number: Int

    private(set) var phase: Phase = .starting

    /// What the terminal UI draws on. Replaced by each attach, so a view keyed
    /// on ``generation`` starts over with it.
    private(set) var screen: TerminalScreen?
    private(set) var generation = 0

    /// Whether it wrote anything in the last sample that typing did not
    /// explain, or is reporting progress. See ``sample(now:)``.
    private(set) var isWorking = false

    /// When it last wrote anything, or was opened.
    private(set) var lastActivity = Date()

    @ObservationIgnored private var seenOutput = 0
    @ObservationIgnored private var seenInput = 0
    @ObservationIgnored private var seenBells = 0

    /// How much had been typed when it last rang the bell, as
    /// ``TerminalScreen/notification`` keeps for a notification.
    private var bellInputCount: Int?

    /// Told when the process exits, with how.
    @ObservationIgnored var onExit: ((AgentTab, Int32) -> Void)?

    @ObservationIgnored private var process: (any PTYSession)?
    @ObservationIgnored private var watching: Task<Void, Never>?

    init(agent: Agent, number: Int) {
        self.agent = agent
        self.number = number
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
            screen = TerminalScreen(session: session, size: spec.size)
            seenOutput = 0
            seenInput = 0
            seenBells = 0
            bellInputCount = nil
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
    /// second: output in that time is work, unless it was the echo of typing.
    func sample(now: Date) {
        guard let screen else { return }
        let output = screen.outputCount
        let input = screen.inputCount
        let wrote = output != seenOutput
        let typed = input != seenInput
        seenOutput = output
        seenInput = input
        if wrote { lastActivity = now }
        if screen.bellCount != seenBells {
            seenBells = screen.bellCount
            bellInputCount = input
        }
        let working = screen.isReportingProgress || (wrote && !typed)
        if isWorking != working { isWorking = working }
    }

    /// A bell or a notification that nothing has been typed since.
    private var attention: String?? {
        guard let screen else { return nil }
        if let notification = screen.notification, notification.inputCount == screen.inputCount {
            return .some(notification.text.isEmpty ? nil : notification.text)
        }
        if bellInputCount == screen.inputCount { return .some(nil) }
        return nil
    }

    var state: AgentSessionSummary.State {
        switch phase {
        case .starting: return .starting
        case .failed: return .failed
        case .exited(let code): return .exited(code)
        case .running:
            if let attention { return .needsInput(attention) }
            return isWorking ? .working : .idle
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
}
