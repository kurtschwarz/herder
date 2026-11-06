import Core
import Foundation
import Observation
import TerminalUI

/// One shell in the panel: its screen, what to call it, and whether it is busy.
@Observable
final class TerminalTab: Identifiable {
    let id = UUID()
    let screen: TerminalScreen

    /// What the foreground process is, as a tab would say it.
    private(set) var title = TerminalTitle.placeholder

    /// Where the shell is: what it said, or else what the system says.
    private(set) var directory: URL?

    /// Something other than the shell is in the foreground.
    private(set) var isBusy = false

    /// Set once the shell has gone.
    private(set) var exitCode: Int32?

    /// Told when the shell exits, with how.
    @ObservationIgnored var onExit: ((TerminalTab, Int32) -> Void)?

    @ObservationIgnored private let session: any PTYSession
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    init(session: any PTYSession, size: PTYSize, directory: URL) {
        self.session = session
        self.directory = directory
        screen = TerminalScreen(session: session, size: size)
    }

    deinit {
        for task in tasks { task.cancel() }
    }

    /// Watches the process: for its exit, and, while it lives, for what is in
    /// front and where it is, once a `period`.
    ///
    /// Polled, because the kernel offers no notification for either and
    /// neither is worth more than a pair of cheap system calls a second.
    func start(clock: any ClockClient, period: Duration = .seconds(1)) {
        tasks.append(Task { [weak self, session] in
            let code = await session.waitForExit()
            self?.didExit(code)
        })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await clock.sleep(for: period) } catch { return }
            }
        })
    }

    func refresh() async {
        guard exitCode == nil else { return }
        let process = await session.foregroundProcess()
        let title = TerminalTitle.make(for: process)
        if self.title != title { self.title = title }
        let busy = process.map { !$0.isShell } ?? false
        if isBusy != busy { isBusy = busy }

        let directory = if let reported = screen.reportedDirectory { reported } else { await session.workingDirectory() }
        if let directory, self.directory != directory { self.directory = directory }
    }

    /// Whether the shell is running something now, asked of the process
    /// itself: a command started a moment ago is not in ``isBusy`` yet.
    func isRunningSomething() async -> Bool {
        guard exitCode == nil, let process = await session.foregroundProcess() else { return false }
        return !process.isShell
    }

    private func didExit(_ code: Int32) {
        exitCode = code
        isBusy = false
        for task in tasks { task.cancel() }
        onExit?(self, code)
    }

    /// Hangs up and stops watching. The exit that follows is not reported:
    /// whoever hung up knows.
    func terminate() {
        onExit = nil
        for task in tasks { task.cancel() }
        session.terminate()
    }
}
