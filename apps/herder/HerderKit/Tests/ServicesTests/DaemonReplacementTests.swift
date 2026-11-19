import Core
import Darwin
import Foundation
import Synchronization
@testable import Services
import Testing

/// What the app does when the daemon on its socket speaks no version it does:
/// replaces an older one that owns no sessions, and leaves any other alone.
///
/// The daemon on the socket is a stand-in that gives one fixed answer to every
/// hello, run as its own process so that ending it is ending a real process.
/// Its executable is not named `herderd`, so these tests pass a `terminate`
/// that skips that check and does the rest of what the app does.
@Suite(.serialized, .timeLimit(.minutes(1))) struct DaemonReplacementTests {
    let socket = URL(filePath: "/tmp/herderd-old-\(UUID().uuidString.prefix(8)).sock")

    static let oldDaemon = #"{"type":"incompatible","min_protocol":1,"max_protocol":1,"daemon_version":"0.1.0"}"#

    /// Answers every hello with `reply`, until it is ended. It forks and its
    /// parent exits, so like a real daemon it is not this process's child,
    /// and once ended it is gone rather than left as a zombie.
    final class StandIn {
        let pid: pid_t

        init(socket: URL, reply: String) throws {
            let script = """
                import os, socket, struct, sys
                path, reply = sys.argv[1], sys.argv[2].encode()
                child = os.fork()
                if child:
                    print(child, flush=True)
                    os._exit(0)
                os.setsid()
                quiet = os.open(os.devnull, os.O_RDWR)
                for descriptor in (0, 1, 2):
                    os.dup2(quiet, descriptor)
                server = socket.socket(socket.AF_UNIX)
                server.bind(path)
                server.listen(16)
                while True:
                    client, _ = server.accept()
                    try:
                        length = struct.unpack(">I", client.recv(4))[0]
                        received = b""
                        while len(received) < length:
                            received += client.recv(length - len(received))
                        client.sendall(struct.pack(">I", len(reply)) + reply)
                    finally:
                        client.close()
                """
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(filePath: "/usr/bin/python3")
            process.arguments = ["-I", "-c", script, socket.path(percentEncoded: false), reply]
            process.standardOutput = output
            try process.run()
            process.waitUntilExit()
            let printed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            pid = try #require(pid_t(printed.trimmingCharacters(in: .whitespacesAndNewlines)))

            let deadline = Date.now.addingTimeInterval(10)
            while !FileManager.default.fileExists(atPath: socket.path(percentEncoded: false)), Date.now < deadline {
                usleep(20_000)
            }
        }

        var isRunning: Bool { kill(pid, 0) == 0 }

        deinit { kill(pid, SIGKILL) }
    }

    /// The pids the client ended.
    final class Ended: Sendable {
        private let pids = Mutex<[pid_t]>([])
        func append(_ pid: pid_t) { pids.withLock { $0.append(pid) } }
        var all: [pid_t] { pids.withLock { $0 } }
    }

    func client(ending ended: Ended) -> LiveDaemonClient {
        LiveDaemonClient(
            socket: socket, executable: LiveDaemonClientTests.binary, client: "test",
            terminate: { pid in
                ended.append(pid)
                return LiveDaemonClient.end(pid)
            }
        )
    }

    func cleanUp(_ client: LiveDaemonClient) {
        client.launchedPIDs.forEach { kill($0, SIGKILL) }
        try? FileManager.default.removeItem(at: socket)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func anOlderDaemonWithNoSessionsIsReplacedWithTheBundledOne() async throws {
        let old = try StandIn(socket: socket, reply: Self.oldDaemon)
        let ended = Ended()
        let client = client(ending: ended)
        defer { cleanUp(client) }

        let status = await client.connect()

        guard case .connected(let info) = status else {
            Issue.record("expected connected, got \(status)")
            return
        }
        #expect(info.protocolVersion == DaemonWire.supported.upperBound)
        #expect(ended.all == [old.pid])
        #expect(!old.isRunning)
        #expect(client.launchedPIDs.count == 1)
    }

    /// The path an update takes: the first thing the app asks for is git, not
    /// the Settings status.
    @Test(.enabled(if: LiveDaemonClientTests.built))
    func aRequestToAnOlderDaemonReplacesItAndIsAnswered() async throws {
        let old = try StandIn(socket: socket, reply: Self.oldDaemon)
        let ended = Ended()
        let client = client(ending: ended)
        defer { cleanUp(client) }

        let kind = try await DaemonGitClient(daemon: client).repositoryKind(at: URL(filePath: "/tmp"))

        #expect(kind == .notARepository)
        #expect(ended.all == [old.pid])
    }

    @Test(
        .enabled(if: LiveDaemonClientTests.built),
        arguments: [
            // It owns sessions.
            #"{"type":"incompatible","min_protocol":1,"max_protocol":1,"daemon_version":"0.1.0","sessions":1}"#,
            // Newer than this app.
            #"{"type":"incompatible","min_protocol":9,"max_protocol":9,"daemon_version":"9.0.0","sessions":0}"#,
        ]
    )
    func anyOtherIncompatibleDaemonIsLeftRunning(reply: String) async throws {
        let other = try StandIn(socket: socket, reply: reply)
        let ended = Ended()
        let client = client(ending: ended)
        defer { cleanUp(client) }

        guard case .incompatible = await client.connect() else {
            Issue.record("expected incompatible")
            return
        }
        #expect(ended.all.isEmpty)
        #expect(other.isRunning)
        #expect(client.launchedPIDs.isEmpty)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func onlyAProcessRunningHerderdIsTakenForTheDaemon() async throws {
        let starter = LiveDaemonClient(socket: socket, executable: LiveDaemonClientTests.binary, client: "test")
        defer { cleanUp(starter) }
        guard case .connected = await starter.connect(), let pid = starter.launchedPIDs.first else {
            Issue.record("expected the daemon to start")
            return
        }

        #expect(LiveDaemonClient.isDaemon(pid))
        #expect(!LiveDaemonClient.isDaemon(getpid()))
        let other = try StandIn(socket: URL(filePath: "/tmp/herderd-not-\(UUID().uuidString.prefix(8)).sock"), reply: "")
        #expect(!LiveDaemonClient.isDaemon(other.pid))
        #expect(!LiveDaemonClient.terminateDaemon(other.pid))
        #expect(other.isRunning)
    }
}
