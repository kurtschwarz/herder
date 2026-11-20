import Core
import Darwin
import Foundation
@testable import Services
import Testing

/// Against the real `herderd` binary, which `just test` builds first. A run
/// without it (a bare `swift test`) skips these rather than failing.
@Suite(.serialized, .timeLimit(.minutes(1))) struct LiveDaemonClientTests {
    static let binary = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "packages/herderd/target/herderd")

    static let built = FileManager.default.isExecutableFile(atPath: binary.path(percentEncoded: false))

    /// Short, because a Unix socket path holds about a hundred bytes.
    let socket = URL(filePath: "/tmp/herderd-test-\(UUID().uuidString.prefix(8)).sock")

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func startsTheDaemonThenFindsItRunning() async {
        let starter = LiveDaemonClient(socket: socket, executable: Self.binary, client: "test")
        defer {
            starter.launchedPIDs.forEach { kill($0, SIGKILL) }
            try? FileManager.default.removeItem(at: socket)
        }

        let started = await starter.connect()
        guard case .connected(let info) = started else {
            Issue.record("expected connected, got \(started)")
            return
        }
        #expect(info.protocolVersion == DaemonWire.supported.upperBound)
        #expect(info.host == "local")
        #expect(starter.launchedPIDs.count == 1)

        // A second client with nothing to start finds the one that is running.
        let finder = LiveDaemonClient(socket: socket, executable: nil, client: "test")
        #expect(await finder.connect() == started)
        #expect(finder.launchedPIDs.isEmpty)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func relaunchingAfterAnIdleExitStartsTheBundledBinaryAgain() async throws {
        let first = LiveDaemonClient(
            socket: socket, executable: Self.binary, client: "test", daemonArguments: ["--idle-timeout", "1"],
            startTimeout: .seconds(20)
        )
        let second = LiveDaemonClient(socket: socket, executable: Self.binary, client: "test")
        defer {
            (first.launchedPIDs + second.launchedPIDs).forEach { kill($0, SIGKILL) }
            try? FileManager.default.removeItem(at: socket)
        }

        guard case .connected = await first.connect() else {
            Issue.record("expected the first daemon to start")
            return
        }
        let oldPID = try #require(first.launchedPIDs.first)

        #expect(FileManager.default.fileExists(atPath: socket.path(percentEncoded: false)))

        // Once the client lets go the daemon is idle and leaves, taking its
        // socket with it.
        first.disconnect()
        let deadline = ContinuousClock.now + .seconds(30)
        while FileManager.default.fileExists(atPath: socket.path(percentEncoded: false)), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!FileManager.default.fileExists(atPath: socket.path(percentEncoded: false)))
        var status: Int32 = 0
        #expect(waitpid(oldPID, &status, 0) == oldPID)

        guard case .connected = await second.connect() else {
            Issue.record("expected a new daemon to start")
            return
        }
        #expect(second.launchedPIDs.count == 1)
        #expect(second.launchedPIDs.first != oldPID)
    }

    /// The Swift half of the GitHub messages against the real daemon. Clearing
    /// needs no network, so what comes back is the daemon's own answer.
    @Test(.enabled(if: LiveDaemonClientTests.built))
    func theDaemonAnswersAGitHubMessage() async throws {
        let client = LiveDaemonClient(socket: socket, executable: Self.binary, client: "test")
        defer {
            client.launchedPIDs.forEach { kill($0, SIGKILL) }
            try? FileManager.default.removeItem(at: socket)
        }

        let reply = try await client.request(DaemonWire.clearGitHubToken(id: 3))

        #expect(DaemonWire.gitHubCheck(fromReply: reply, id: 3) == .notConnected)
    }

    @Test func nothingListeningAndNothingToStartIsUnavailable() async {
        let client = LiveDaemonClient(socket: socket, executable: nil, client: "test")

        guard case .unavailable = await client.connect() else {
            Issue.record("expected unavailable")
            return
        }
    }

    @Test func aDaemonThatCannotBeStartedIsUnavailable() async {
        struct Refused: Error {}
        let client = LiveDaemonClient(
            socket: socket, executable: URL(filePath: "/nowhere/herderd"), client: "test",
            launch: { _, _ in throw Refused() }
        )

        guard case .unavailable = await client.connect() else {
            Issue.record("expected unavailable")
            return
        }
    }

    @Test func aDaemonThatNeverAnswersIsUnavailableOnceTheTimeoutPasses() async {
        let client = LiveDaemonClient(
            socket: socket, executable: URL(filePath: "/bin/true"), client: "test",
            startTimeout: .milliseconds(200), launch: { _, _ in 0 }
        )

        guard case .unavailable = await client.connect() else {
            Issue.record("expected unavailable")
            return
        }
    }

    @Test func aPathTooLongForASocketIsUnavailable() async {
        let long = URL(filePath: "/tmp/" + String(repeating: "x", count: 200) + ".sock")
        let client = LiveDaemonClient(socket: long, executable: nil, client: "test")

        guard case .unavailable = await client.connect() else {
            Issue.record("expected unavailable")
            return
        }
    }

    @Test func aDebugBuildHasItsOwnSocket() throws {
        #if DEBUG
        #expect(LiveDaemonClient.socketName == "herderd-dev.sock")
        #else
        #expect(LiveDaemonClient.socketName == "herderd.sock")
        #endif
        #expect(try LiveDaemonClient.socketURL().lastPathComponent == LiveDaemonClient.socketName)
    }
}
