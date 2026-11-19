#if DEBUG
import Core
import Foundation
import Synchronization

/// ``GitHubAuthClient`` that answers from a script. Each poll and each refresh
/// takes the next answer; when the script runs out the last one repeats.
public final class StubGitHubAuthClient: GitHubAuthClient {
    private struct State {
        var code: Result<GitHubDeviceCode, GitHubAuthError>
        var polls: [Result<GitHubDevicePoll, GitHubAuthError>] = []
        var refreshes: [Result<GitHubTokens, GitHubAuthError>] = []
        var polled: [String] = []
        var refreshed: [String] = []
        var onPoll: (@Sendable () -> Void)?
    }

    private let state: Mutex<State>

    public init(code: Result<GitHubDeviceCode, GitHubAuthError> = .success(StubGitHubAuthClient.deviceCode)) {
        state = Mutex(State(code: code))
    }

    public static let deviceCode = GitHubDeviceCode(
        deviceCode: "device-code",
        userCode: "WDJB-MJHT",
        verificationURL: URL(string: "https://github.com/login/device")!,
        expiresIn: .seconds(900),
        interval: .seconds(5)
    )

    /// Runs before each poll answers, so a test can look at what the app shows
    /// while it waits.
    public func onPoll(_ hook: @escaping @Sendable () -> Void) {
        state.withLock { $0.onPoll = hook }
    }

    public func script(polls: [Result<GitHubDevicePoll, GitHubAuthError>]) {
        state.withLock { $0.polls = polls }
    }

    public func script(refreshes: [Result<GitHubTokens, GitHubAuthError>]) {
        state.withLock { $0.refreshes = refreshes }
    }

    /// The device codes polled with, in order.
    public var polled: [String] { state.withLock { $0.polled } }

    /// The refresh tokens refreshed with, in order.
    public var refreshed: [String] { state.withLock { $0.refreshed } }

    public func requestDeviceCode() async throws -> GitHubDeviceCode {
        try state.withLock { $0.code }.get()
    }

    public func poll(deviceCode: String) async throws -> GitHubDevicePoll {
        let hook = state.withLock { $0.onPoll }
        hook?()
        return try state.withLock { state in
            state.polled.append(deviceCode)
            return Self.next(&state.polls) ?? .success(.pending)
        }.get()
    }

    public func refresh(using refreshToken: String) async throws -> GitHubTokens {
        try state.withLock { state in
            state.refreshed.append(refreshToken)
            return Self.next(&state.refreshes) ?? .failure(.unexpected("nothing scripted"))
        }.get()
    }

    private static func next<Element>(_ script: inout [Element]) -> Element? {
        script.count > 1 ? script.removeFirst() : script.first
    }
}
#endif
