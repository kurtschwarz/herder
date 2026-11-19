import Foundation
import Synchronization
import Testing
import TestSupport

@testable import Core

/// A daemon that answers the GitHub messages from a script: what `set` finds
/// each time, in order, the last one repeating.
final class GitHubDaemon: Sendable {
    let client = StubDaemonClient()
    private let checks: Mutex<[GitHubCheck]>
    private let reachable = Mutex(true)

    init(_ checks: [GitHubCheck] = [.ok(login: "kurt")]) {
        self.checks = Mutex(checks)
        client.respond { [self] payload in
            guard reachable.withLock({ $0 }),
                  let message = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
                  let id = message["id"] as? Int
            else { throw StubDaemonClientError.unreachable }
            let connection: String
            switch message["type"] as? String {
            case "set_github_token", "check_github":
                connection = Self.json(next())
            default:
                connection = #"{"state":"not_connected"}"#
            }
            return Data(#"{"type":"github_response","id":\#(id),"check":\#(connection)}"#.utf8)
        }
    }

    func setReachable(_ value: Bool) { reachable.withLock { $0 = value } }

    private func next() -> GitHubCheck {
        checks.withLock { $0.count > 1 ? $0.removeFirst() : $0[0] }
    }

    private static func json(_ check: GitHubCheck) -> String {
        switch check {
        case .ok(let login): #"{"state":"ok","login":"\#(login)"}"#
        case .unauthorized: #"{"state":"unauthorized"}"#
        case .notConnected: #"{"state":"not_connected"}"#
        case .error(let message): #"{"state":"error","message":"\#(message)"}"#
        }
    }

    /// What was sent, as the message type and the token if it had one.
    var sent: [(type: String, token: String?)] {
        client.requests.compactMap { payload in
            let message = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
            return (message?["type"] as? String).map { ($0, message?["token"] as? String) }
        }
    }

    var tokensHandedOver: [String] { sent.filter { $0.type == "set_github_token" }.compactMap(\.token) }
    var clears: Int { sent.filter { $0.type == "clear_github_token" }.count }
}

func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}

@Suite(.timeLimit(.minutes(1))) @MainActor struct GitHubConnectionTests {
    let clock = VirtualClockClient()
    let auth = StubGitHubAuthClient()
    let vault = InMemoryGitHubTokenVault()
    private let daemon: GitHubDaemon
    let origin = Date(timeIntervalSince1970: 1_700_000_000)
    let began: ContinuousClock.Instant
    let model: GitHubConnection

    init() {
        let daemon = GitHubDaemon()
        began = clock.now
        self.daemon = daemon
        model = Self.connection(
            auth: auth, vault: vault, daemon: daemon, clock: clock, origin: origin, began: began
        )
    }

    /// A connection whose wall time moves exactly as far as its clock was slept.
    static func connection(
        auth: any GitHubAuthClient, vault: any GitHubTokenVault, daemon: GitHubDaemon,
        clock: VirtualClockClient, origin: Date, began: ContinuousClock.Instant
    ) -> GitHubConnection {
        GitHubConnection(
            auth: auth, vault: vault, daemon: daemon.client, clock: clock,
            now: { origin.addingTimeInterval(seconds(clock.now - began)) }
        )
    }

    private func connection(checking checks: [GitHubCheck]) -> (GitHubConnection, GitHubDaemon) {
        let daemon = GitHubDaemon(checks)
        let model = Self.connection(
            auth: auth, vault: vault, daemon: daemon, clock: clock, origin: origin, began: began
        )
        return (model, daemon)
    }

    /// The wall time now, by the same clock the model reads.
    var wall: Date { origin.addingTimeInterval(seconds(clock.now - began)) }

    func tokens(
        _ name: String, accessIn access: TimeInterval = 3600, refreshIn refresh: TimeInterval = 15_000_000
    ) -> GitHubTokens {
        GitHubTokens(
            accessToken: "access-\(name)", refreshToken: "refresh-\(name)",
            accessExpiresAt: wall.addingTimeInterval(access), refreshExpiresAt: wall.addingTimeInterval(refresh)
        )
    }

    /// Lets the model's background tasks run until `condition` holds.
    func until(_ condition: () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("gave up waiting")
    }

    // MARK: - Launch

    @Test func withNothingStoredItIsNotConnectedAndTellsHerderdToForgetAnyToken() async {
        await model.start()

        #expect(model.state == .notConnected)
        #expect(daemon.tokensHandedOver.isEmpty)
        #expect(daemon.clears == 1)
    }

    @Test func storedTokensAreHandedToHerderdAndShowWhoTheyBelongTo() async {
        vault.seed(tokens("one"))

        await model.start()

        #expect(model.state == .connected(login: "kurt"))
        #expect(daemon.tokensHandedOver == ["access-one"])
        #expect(auth.refreshed.isEmpty)
        await model.signOut()
    }

    @Test func anExpiredAccessTokenIsRefreshedAtLaunch() async {
        vault.seed(tokens("old", accessIn: -60))
        let renewed = tokens("new")
        auth.script(refreshes: [.success(renewed), .failure(.refreshTokenRejected)])

        await model.start()

        #expect(auth.refreshed == ["refresh-old"])
        #expect(vault.tokens == renewed)
        #expect(daemon.tokensHandedOver == ["access-new"])
        #expect(model.state == .connected(login: "kurt"))
        await model.signOut()
    }

    @Test func anAccessTokenInItsLastFiveMinutesIsRefreshedAtLaunch() async {
        vault.seed(tokens("old", accessIn: 4 * 60))
        auth.script(refreshes: [.success(tokens("new"))])

        await model.start()

        #expect(auth.refreshed == ["refresh-old"])
        await model.signOut()
    }

    @Test func anExpiredRefreshTokenAsksForReconnect() async {
        vault.seed(tokens("old", accessIn: -60, refreshIn: -1))

        await model.start()

        #expect(model.state == .reconnect)
        #expect(auth.refreshed.isEmpty)
        #expect(daemon.tokensHandedOver.isEmpty)
        #expect(daemon.clears == 1)
    }

    @Test func aRefreshTokenGitHubRefusesAsksForReconnect() async {
        vault.seed(tokens("old", accessIn: -60))
        auth.script(refreshes: [.failure(.refreshTokenRejected)])

        await model.start()

        #expect(model.state == .reconnect)
        #expect(daemon.clears == 1)
    }

    @Test func aKeychainThatCannotBeReadIsNotConnectedWithTheReason() async {
        vault.failLoading()

        await model.start()

        #expect(model.state == .notConnected)
        #expect(model.lastError?.contains("Keychain") == true)
    }

    // MARK: - Refreshing

    @Test func tokensAreRefreshedFiveMinutesBeforeTheyExpireAndTheNewOneIsHandedOver() async {
        vault.seed(tokens("one"))
        // What the refresh at 55 minutes returns expires an hour after that.
        let renewed = GitHubTokens(
            accessToken: "access-two", refreshToken: "refresh-two",
            accessExpiresAt: origin.addingTimeInterval(55 * 60 + 3600),
            refreshExpiresAt: origin.addingTimeInterval(15_000_000)
        )
        auth.script(refreshes: [.success(renewed), .failure(.refreshTokenRejected)])

        await model.start()
        await until { model.state == .reconnect }

        let expected: [Duration] = [.seconds(55 * 60), .seconds(55 * 60)]
        #expect(Array(clock.sleeps.prefix(2)) == expected)
        #expect(auth.refreshed == ["refresh-one", "refresh-two"])
        #expect(vault.saved == [renewed])
        #expect(daemon.tokensHandedOver == ["access-one", "access-two"])
    }

    @Test func aRefreshThatCannotReachGitHubKeepsTheTokensAndTriesAgainInAMinute() async {
        vault.seed(tokens("one"))
        // Renewed after the retry, so an hour from then.
        let renewed = GitHubTokens(
            accessToken: "access-two", refreshToken: "refresh-two",
            accessExpiresAt: origin.addingTimeInterval(55 * 60 + 60 + 3600),
            refreshExpiresAt: origin.addingTimeInterval(15_000_000)
        )
        auth.script(refreshes: [.failure(.network("offline")), .success(renewed), .failure(.refreshTokenRejected)])

        await model.start()
        await until { model.state == .reconnect }

        let expected: [Duration] = [.seconds(55 * 60), GitHubConnection.retryDelay, .seconds(55 * 60)]
        #expect(Array(clock.sleeps.prefix(3)) == expected)
        #expect(auth.refreshed == ["refresh-one", "refresh-one", "refresh-two"])
        #expect(vault.saved == [renewed])
    }

    @Test func aTokenGitHubRefusesBeforeItExpiresIsRefreshedOnce() async {
        let (model, daemon) = connection(checking: [.unauthorized, .ok(login: "kurt")])
        vault.seed(tokens("one"))
        auth.script(refreshes: [.success(tokens("two")), .failure(.refreshTokenRejected)])

        await model.start()

        #expect(model.state == .connected(login: "kurt"))
        #expect(auth.refreshed == ["refresh-one"])
        #expect(daemon.tokensHandedOver == ["access-one", "access-two"])
        await model.signOut()
    }

    @Test func aFreshTokenGitHubRefusesAsksForReconnect() async {
        let (model, _) = connection(checking: [.unauthorized])
        vault.seed(tokens("one"))
        auth.script(refreshes: [.success(tokens("two"))])

        await model.start()

        #expect(model.state == .reconnect)
        #expect(auth.refreshed == ["refresh-one"])
        await model.signOut()
    }

    // MARK: - herderd

    @Test func aDaemonThatCannotBeReachedLeavesTheTokenUnverifiedUntilAskedAgain() async {
        vault.seed(tokens("one"))
        daemon.setReachable(false)

        await model.start()
        guard case .unverified = model.state else {
            Issue.record("expected unverified, got \(model.state)")
            return
        }

        daemon.setReachable(true)
        await model.recheck()

        #expect(model.state == .connected(login: "kurt"))
        await model.signOut()
    }

    @Test func aCheckThatFindsAnErrorIsUnverifiedWithItsMessage() async {
        let (model, _) = connection(checking: [.error("GitHub answered 502")])
        vault.seed(tokens("one"))

        await model.start()

        #expect(model.state == .unverified(reason: "GitHub answered 502"))
        await model.signOut()
    }

    // MARK: - Signing in

    @Test func signingInShowsTheCodeThenSavesTheTokensAndConnects() async {
        let signedIn = tokens("fresh")
        auth.script(polls: [.success(.pending), .success(.slowDown), .success(.signedIn(signedIn))])
        let shown = Mutex<[GitHubConnectionState]>([])
        let model = model
        auth.onPoll { shown.withLock { $0.append(MainActor.assumeIsolated { model.state }) } }

        await model.signIn()

        #expect(shown.withLock { $0 }.allSatisfy { $0 == .signingIn(StubGitHubAuthClient.deviceCode) })
        #expect(auth.polled == ["device-code", "device-code", "device-code"])
        // The interval GitHub asked for, then five seconds longer once it said slow down.
        let expected: [Duration] = [.seconds(5), .seconds(5), .seconds(10)]
        #expect(Array(clock.sleeps.prefix(3)) == expected)
        #expect(vault.tokens == signedIn)
        #expect(daemon.tokensHandedOver == ["access-fresh"])
        #expect(model.state == .connected(login: "kurt"))
        #expect(model.lastError == nil)
        await model.signOut()
    }

    @Test func aRefusalOnGitHubReturnsToNotConnectedWithTheReason() async {
        auth.script(polls: [.success(.denied)])

        await model.signIn()

        #expect(model.state == .notConnected)
        #expect(model.lastError == "Sign-in was refused on GitHub.")
        #expect(vault.tokens == nil)
    }

    @Test func aCodeThatExpiresReturnsToNotConnectedWithTheReason() async {
        auth.script(polls: [.success(.expired)])

        await model.signIn()

        #expect(model.state == .notConnected)
        #expect(model.lastError == "The code expired before it was used.")
    }

    @Test func aCodeThatIsNeverUsedExpiresOnItsOwn() async {
        await model.signIn()

        #expect(model.state == .notConnected)
        #expect(model.lastError == "The code expired before it was used.")
    }

    @Test(arguments: [
        (GitHubAuthError.notConfigured, "This build of Herder has no GitHub App to sign in to."),
        (GitHubAuthError.network("offline"), "Could not reach GitHub: offline"),
    ])
    func aFlowThatCannotStartSaysWhy(error: GitHubAuthError, message: String) async {
        let auth = StubGitHubAuthClient(code: .failure(error))
        let model = GitHubConnection(auth: auth, vault: vault, daemon: daemon.client, clock: clock)

        await model.signIn()

        #expect(model.state == .notConnected)
        #expect(model.lastError == message)
    }

    @Test func aReconnectThatIsGivenUpOnStaysReconnect() async {
        vault.seed(tokens("old", accessIn: -60, refreshIn: -1))
        await model.start()
        auth.script(polls: [.success(.denied)])

        await model.signIn()

        #expect(model.state == .reconnect)
    }

    @Test func aTokenThatCannotBeSavedIsNotUsed() async {
        vault.failSaving()
        auth.script(polls: [.success(.signedIn(tokens("fresh")))])

        await model.signIn()

        #expect(model.state == .notConnected)
        #expect(model.lastError?.contains("Keychain") == true)
        #expect(daemon.tokensHandedOver.isEmpty)
    }

    @Test func cancellingASignInReturnsToNotConnectedWithoutAnError() async {
        let model = model
        auth.onPoll { MainActor.assumeIsolated { model.cancelSignIn() } }

        await model.signIn()

        #expect(model.state == .notConnected)
        #expect(model.lastError == nil)
    }

    @Test func aSignInCancelledAsItsAnswerArrivesIsNotUsed() async {
        let model = model
        auth.script(polls: [.success(.signedIn(tokens("fresh")))])
        auth.onPoll { MainActor.assumeIsolated { model.cancelSignIn() } }

        await model.signIn()

        #expect(model.state == .notConnected)
        #expect(vault.tokens == nil)
        #expect(daemon.tokensHandedOver.isEmpty)
    }

    // MARK: - Signing out

    @Test func signingOutDeletesTheKeychainItemAndTellsHerderdToForget() async {
        vault.seed(tokens("one"))
        auth.script(refreshes: [.success(tokens("two"))])
        await model.start()

        await model.signOut()

        #expect(model.state == .notConnected)
        #expect(vault.tokens == nil)
        #expect(vault.deletes == 1)
        #expect(daemon.clears == 1)
    }

    @Test func signingOutStopsTheRefreshes() async {
        vault.seed(tokens("one"))
        auth.script(refreshes: [.success(tokens("two"))])
        await model.start()
        await model.signOut()

        for _ in 0..<100 { await Task.yield() }

        #expect(auth.refreshed.isEmpty)
    }
}
