import Foundation
import Observation

/// Finds the pull request of each session's branch and links it to the
/// session, by asking herderd about every watched branch on a timer.
///
/// The app drives it because herderd cannot push yet: each poll sends the
/// branches worth asking about (see ``AgentSessions/watchedBranches()``) and
/// herderd makes one request to GitHub for all of them. herderd answers with
/// how long to wait for the next poll, which grows while GitHub cannot be
/// reached. Errors are for Settings to show and nothing else does. See ADR 0003.
///
/// Nothing is asked while the app is closed, so the first poll after a launch
/// catches up. App-wide, like the GitHub connection it reads through.
///
/// The annotation is explicit because `Core` keeps the nonisolated default.
@MainActor
@Observable
public final class LinkedPullRequests {
    /// A repository herderd could not read, because the GitHub App is not
    /// installed on it.
    public struct Inaccessible: Equatable, Sendable, Identifiable {
        /// `owner/name`.
        public var name: String
        public var id: String { name }
    }

    /// How long to wait for the next poll when herderd says nothing: when it
    /// cannot be reached.
    public static let pollInterval: Duration = .seconds(60)

    /// The longest to wait after failing to reach herderd.
    public static let maxBackoff: Duration = .seconds(600)

    /// How long to wait before looking again when there was nothing to ask
    /// about. Nothing leaves the app for it.
    public static let idleInterval: Duration = .seconds(5)

    /// Repositories GitHub said the App cannot see, as of the last poll.
    public private(set) var inaccessible: [Inaccessible] = []

    /// What went wrong with the last poll, for Settings: GitHub could not be
    /// asked, or herderd could not be reached. `nil` once one has worked.
    public private(set) var lastError: String?

    @ObservationIgnored private let sessions: AgentSessions
    @ObservationIgnored private let daemon: any DaemonClient
    @ObservationIgnored private let clock: any ClockClient
    @ObservationIgnored private let signInRefused: @MainActor () async -> Void

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestID = 0
    @ObservationIgnored private var daemonFailures = 0

    /// What each repository's default branch is, once GitHub has said: a
    /// branch with no use asking about.
    @ObservationIgnored private var defaultBranches: [PathKey: String] = [:]

    /// - Parameter signInRefused: what to do when GitHub refuses the token:
    ///   try to refresh it, and ask for a reconnect if that fails.
    public init(
        sessions: AgentSessions,
        daemon: any DaemonClient,
        clock: any ClockClient,
        signInRefused: @escaping @MainActor () async -> Void
    ) {
        self.sessions = sessions
        self.daemon = daemon
        self.clock = clock
        self.signInRefused = signInRefused
    }

    // MARK: - Running

    /// Starts polling, if it is not already.
    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in await self?.run() }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// Polls until cancelled, waiting as long as each answer asks.
    func run() async {
        while !Task.isCancelled {
            let wait = await poll()
            do { try await clock.sleep(for: wait) } catch { return }
        }
    }

    // MARK: - One poll

    /// Asks about every watched branch, links what was found, and returns how
    /// long to wait before the next poll.
    func poll() async -> Duration {
        var keys: [String: PathKey] = [:]
        var queries: [PullRequestQuery] = []
        for (key, branches) in sessions.watchedBranches().sorted(by: { $0.key < $1.key }) {
            let asked = branches.filter { $0 != defaultBranches[key] }.sorted()
            guard !asked.isEmpty else { continue }
            keys[key.path] = key
            queries.append(PullRequestQuery(path: key.path, branches: asked))
        }
        guard !queries.isEmpty else { return Self.idleInterval }

        let id = nextRequestID()
        let reply: PullRequestReply
        do {
            let payload = try await daemon.request(DaemonWire.pullRequestQuery(id: id, repos: queries))
            guard let parsed = DaemonWire.pullRequests(fromReply: payload, id: id) else {
                return failToReachDaemon("herderd's answer was not one this app understands.")
            }
            reply = parsed
        } catch {
            return failToReachDaemon("herderd could not be reached.")
        }
        daemonFailures = 0

        var unreadable: Set<String> = []
        var problem: String?
        var refused = false
        for repository in reply.repositories {
            guard let key = keys[repository.path] else { continue }
            switch repository.status {
            case .ok:
                break
            case .notAccessible:
                unreadable.insert(repository.name)
            case .unauthorized:
                refused = true
            case .error(let message):
                problem = problem ?? message
            }
            if let defaultBranch = repository.defaultBranch { defaultBranches[key] = defaultBranch }
            // Linked even on an error: what herderd has then is what GitHub last said.
            for (branch, found) in repository.branches {
                guard let pullRequest = found else { continue }
                sessions.link(pullRequest, branch: branch, in: key)
            }
        }
        let unreachable = unreadable.sorted().map { Inaccessible(name: $0) }
        if inaccessible != unreachable { inaccessible = unreachable }
        if lastError != problem { lastError = problem }

        if refused { await signInRefused() }
        return reply.nextPoll
    }

    /// Notes that herderd did not answer, and returns how long to wait: a
    /// minute, then doubling up to ten.
    private func failToReachDaemon(_ message: String) -> Duration {
        daemonFailures += 1
        lastError = message
        let seconds = Self.pollInterval.components.seconds << min(daemonFailures - 1, 10)
        return min(.seconds(seconds), Self.maxBackoff)
    }

    private func nextRequestID() -> Int {
        requestID += 1
        return requestID
    }
}
