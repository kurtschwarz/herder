import Testing
import TestSupport

@testable import Core

@Suite(.timeLimit(.minutes(1))) @MainActor struct DaemonConnectionTests {
    @Test func startsConnecting() {
        #expect(DaemonConnection(client: StubDaemonClient()).status == .connecting)
    }

    @Test func showsWhatTheDaemonAnswered() async {
        let info = DaemonInfo(daemonVersion: "0.1.0", protocolVersion: 1, host: "local")
        let connection = DaemonConnection(client: StubDaemonClient(status: .connected(info)))

        await connection.connect()

        #expect(connection.status == .connected(info))
    }

    @Test func showsAMismatchItCannotNegotiate() async {
        let mismatch = DaemonStatus.incompatible(daemonVersion: "2.0.0", supports: 4...6, app: 1...1)
        let connection = DaemonConnection(client: StubDaemonClient(status: mismatch))

        await connection.connect()

        #expect(connection.status == mismatch)
    }

    @Test func connectingAgainAsksAgain() async {
        let client = StubDaemonClient(status: .unavailable(reason: "down"))
        let connection = DaemonConnection(client: client)
        await connection.connect()

        client.answer(.connected(DaemonInfo(daemonVersion: "0.1.0", protocolVersion: 1, host: "local")))
        await connection.connect()

        #expect(client.calls == 2)
        #expect(connection.status == .connected(DaemonInfo(daemonVersion: "0.1.0", protocolVersion: 1, host: "local")))
    }
}
