import Core
import Darwin
import Foundation
@testable import Services
import Testing

/// Against the real `herderd` binary, which `just test` builds first. A run
/// without it (a bare `swift test`) skips these rather than failing.
@Suite(.timeLimit(.minutes(1))) struct LiveDaemonClientTests {
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
