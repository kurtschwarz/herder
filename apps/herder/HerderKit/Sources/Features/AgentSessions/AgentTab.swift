import Core
import Foundation
import Observation
import TerminalUI

/// One agent session's tab: opencode's terminal UI, running in a terminal of
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

    /// What the tab is called: the order it was opened in, in its workspace.
    /// The terminal UI names its own sessions, and says nothing outside.
    let number: Int

    private(set) var phase: Phase = .starting

    /// What the terminal UI draws on. Replaced by each attach, so a view keyed
    /// on ``generation`` starts over with it.
    private(set) var screen: TerminalScreen?
    private(set) var generation = 0

    /// Told when the process exits, with how.
    @ObservationIgnored var onExit: ((AgentTab, Int32) -> Void)?

    @ObservationIgnored private var process: (any PTYSession)?
    @ObservationIgnored private var watching: Task<Void, Never>?

    init(number: Int) {
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
