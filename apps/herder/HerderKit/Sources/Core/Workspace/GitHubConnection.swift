import Foundation
import Observation

/// The app's GitHub connection, observed by Settings: whether the user is
/// signed in, as whom, and what to do when it stops working.
///
/// App-wide, because there is one account. The app owns the tokens (one
/// Keychain item behind ``GitHubTokenVault``) and signs in and refreshes them
/// itself; herderd is only handed the access token, each time it changes, and
/// confirms it works. See ADR 0003.
///
/// The annotation is explicit because `Core` keeps the nonisolated default.
@MainActor
@Observable
public final class GitHubConnection {
    /// The Info.plist key the GitHub App's client ID is under. Empty in a build
    /// made without one.
    public static let clientIDKey = "HerderGitHubClientID"

    /// How long before an access token expires it is replaced.
    public static let refreshLeeway: Duration = .seconds(5 * 60)

    /// How long to wait before asking again after a refresh that could not
    /// reach GitHub.
    public static let retryDelay: Duration = .seconds(60)

    /// How much longer to wait between polls each time GitHub says `slow_down`.
    private static let slowDownStep: Duration = .seconds(5)

    public private(set) var state: GitHubConnectionState = .checking

    /// Why the last attempt to sign in or sign out failed, until the next one.
    public private(set) var lastError: String?

    @ObservationIgnored private let auth: any GitHubAuthClient
    @ObservationIgnored private let vault: any GitHubTokenVault
    @ObservationIgnored private let daemon: any DaemonClient
    @ObservationIgnored private let clock: any ClockClient
    @ObservationIgnored private let now: @Sendable () -> Date

    @ObservationIgnored private var tokens: GitHubTokens?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var signInTask: Task<Void, Never>?
    @ObservationIgnored private var requestID = 0

    /// - Parameter now: the wall clock, which token expiries are measured
    ///   against. Not the monotonic one: they were set by GitHub's calendar.
    public init(
        auth: any GitHubAuthClient,
        vault: any GitHubTokenVault,
        daemon: any DaemonClient,
        clock: any ClockClient,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.auth = auth
        self.vault = vault
        self.daemon = daemon
        self.clock = clock
        self.now = now
    }

    // MARK: - Launch

    /// Picks up where the last run left off: reads the Keychain, refreshes
    /// tokens that are due or past due, and hands herderd the access token.
    /// Returns once that is done; later refreshes run on their own.
    public func start() async {
        let stored: GitHubTokens?
        do {
            stored = try vault.load()
        } catch {
            lastError = "Could not read the Keychain: \(error.localizedDescription)"
            state = .notConnected
            return
        }
        guard let stored else {
            state = .notConnected
            // Whatever the daemon is holding, it should not be this.
            await forgetInDaemon()
            return
        }
        await adopt(stored)
    }

    // MARK: - Signing in

    /// Runs a device flow to its end: shows the code, polls until the user
    /// finishes on GitHub, and connects. Returns when it has finished, was
    /// cancelled, or failed; ``lastError`` says why when it did not connect.
    public func signIn() async {
        guard signInTask == nil else {
            await signInTask?.value
            return
        }
        lastError = nil
        let task = Task { await runSignIn() }
        signInTask = task
        await task.value
        signInTask = nil
    }

    /// Gives up on a sign-in that is waiting for the user.
    public func cancelSignIn() {
        signInTask?.cancel()
    }

    private func runSignIn() async {
        let previous = state
        let code: GitHubDeviceCode
        do {
            code = try await auth.requestDeviceCode()
        } catch {
            lastError = Self.describe(error)
            state = previous == .checking ? .notConnected : previous
            return
        }
        state = .signingIn(code)

        var interval = code.interval
        let deadline = clock.now.advanced(by: code.expiresIn)
        while !Task.isCancelled, clock.now < deadline {
            do {
                try await clock.sleep(for: interval)
                switch try await auth.poll(deviceCode: code.deviceCode) {
                case .pending:
                    continue
                case .slowDown:
                    interval += Self.slowDownStep
                case .signedIn(let signedIn):
                    await finishSignIn(signedIn)
                    return
                case .denied:
                    return abandonSignIn(because: "Sign-in was refused on GitHub.", returningTo: previous)
                case .expired:
                    return abandonSignIn(because: "The code expired before it was used.", returningTo: previous)
                }
            } catch is CancellationError {
                break
            } catch {
                return abandonSignIn(because: Self.describe(error), returningTo: previous)
            }
        }
        if Task.isCancelled {
            abandonSignIn(because: nil, returningTo: previous)
        } else {
            abandonSignIn(because: "The code expired before it was used.", returningTo: previous)
        }
    }

    private func abandonSignIn(because reason: String?, returningTo previous: GitHubConnectionState) {
        lastError = reason
        state = previous == .checking ? .notConnected : previous
    }

    private func finishSignIn(_ signedIn: GitHubTokens) async {
        do {
            try vault.save(signedIn)
        } catch {
            lastError = "Could not save to the Keychain: \(error.localizedDescription)"
            state = .notConnected
            return
        }
        await adopt(signedIn)
    }

    // MARK: - Signing out

    /// Deletes the stored tokens and tells herderd to forget its copy.
    public func signOut() async {
        refreshTask?.cancel()
        refreshTask = nil
        signInTask?.cancel()
        tokens = nil
        lastError = nil
        state = .notConnected
        do {
            try vault.delete()
        } catch {
            lastError = "Could not remove the token from the Keychain: \(error.localizedDescription)"
        }
        await forgetInDaemon()
    }

    // MARK: - Checking again

    /// Asks herderd again whether the token works, after a check that could
    /// not be made.
    public func recheck() async {
        guard let tokens else { return }
        await adopt(tokens)
    }

    // MARK: - Tokens

    /// Starts using `adopted`: refreshes it if it is due, otherwise hands it
    /// to herderd and schedules its refresh.
    private func adopt(_ adopted: GitHubTokens) async {
        refreshTask?.cancel()
        refreshTask = nil
        tokens = adopted

        guard adopted.refreshExpiresAt > now() else {
            await requireReconnect()
            return
        }
        if isDue(adopted) {
            guard await refresh() else { return }
        } else {
            await handOff(adopted, mayRefreshIfRefused: true)
        }
        scheduleRefresh()
    }

    private func isDue(_ tokens: GitHubTokens) -> Bool {
        let leeway = Double(Self.refreshLeeway.components.seconds)
        return tokens.accessExpiresAt.addingTimeInterval(-leeway) <= now()
    }

    /// Replaces the tokens and hands herderd the new access token. `false`
    /// when the refresh token was refused, so there is nothing left to
    /// refresh. A failure to reach GitHub is `true`: the loop in
    /// ``scheduleRefresh()`` tries again.
    private func refresh() async -> Bool {
        guard let current = tokens else { return false }
        do {
            let renewed = try await auth.refresh(using: current.refreshToken)
            // GitHub honours a refresh token once. Saved before anything else
            // can fail, so a crash after this does not strand the next launch.
            try vault.save(renewed)
            tokens = renewed
            await handOff(renewed, mayRefreshIfRefused: false)
            return true
        } catch GitHubAuthError.refreshTokenRejected {
            await requireReconnect()
            return false
        } catch {
            // The access token may still be good for a while. If herderd does
            // not have it yet, give it that; what went wrong is shown unless
            // that works.
            if case .connected = state { return true }
            if current.accessExpiresAt > now() {
                await handOff(current, mayRefreshIfRefused: false)
                if case .connected = state { return true }
            }
            state = .unverified(reason: Self.describe(error))
            return true
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            var wait = self?.delayUntilDue() ?? .zero
            while !Task.isCancelled {
                guard let clock = self?.clock else { return }
                do { try await clock.sleep(for: wait) } catch { return }
                guard let self else { return }
                let before = tokens
                guard await refresh() else { return }
                // Unchanged means GitHub could not be reached, so ask again
                // soon; otherwise wait for the new tokens to come due.
                wait = tokens == before ? Self.retryDelay : delayUntilDue()
            }
        }
    }

    /// How long until the current access token is within ``refreshLeeway`` of
    /// expiring.
    private func delayUntilDue() -> Duration {
        guard let tokens else { return .zero }
        let leeway = Double(Self.refreshLeeway.components.seconds)
        let seconds = tokens.accessExpiresAt.addingTimeInterval(-leeway).timeIntervalSince(now())
        return .seconds(max(0, seconds))
    }

    private func requireReconnect() async {
        tokens = nil
        state = .reconnect
        await forgetInDaemon()
    }

    // MARK: - herderd

    /// Sends herderd `tokens`' access token and shows what it found. When
    /// GitHub says the token is no good before it should be, tries one refresh
    /// if `mayRefreshIfRefused`.
    private func handOff(_ handed: GitHubTokens, mayRefreshIfRefused: Bool) async {
        let check: GitHubCheck
        do {
            let id = nextRequestID()
            let reply = try await daemon.request(DaemonWire.setGitHubToken(id: id, token: handed.accessToken))
            check = DaemonWire.gitHubCheck(fromReply: reply, id: id)
        } catch {
            check = .error("herderd could not be reached.")
        }

        switch check {
        case .ok(let login):
            lastError = nil
            state = .connected(login: login)
        case .unauthorized:
            if mayRefreshIfRefused {
                _ = await refresh()
            } else {
                await requireReconnect()
            }
        case .notConnected:
            state = .unverified(reason: "herderd did not keep the token.")
        case .error(let message):
            state = .unverified(reason: message)
        }
    }

    private func forgetInDaemon() async {
        _ = try? await daemon.request(DaemonWire.clearGitHubToken(id: nextRequestID()))
    }

    private func nextRequestID() -> Int {
        requestID += 1
        return requestID
    }

    private static func describe(_ error: any Error) -> String {
        switch error {
        case GitHubAuthError.notConfigured: "This build of Herder has no GitHub App to sign in to."
        case GitHubAuthError.refreshTokenRejected: "GitHub no longer accepts this sign-in."
        case GitHubAuthError.network(let message): "Could not reach GitHub: \(message)"
        case GitHubAuthError.unexpected(let message): message
        default: error.localizedDescription
        }
    }
}
