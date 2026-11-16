import Foundation
import Testing

@testable import Core

/// The Swift half of the protocol in `packages/herderd/src/protocol.rs`.
@Suite struct DaemonWireTests {
    private func json(_ text: String) -> Data { Data(text.utf8) }

    @Test func aFrameIsABigEndianLengthThenThePayload() {
        let framed = DaemonWire.frame(Data([1, 2, 3]))

        #expect(Array(framed) == [0, 0, 0, 3, 1, 2, 3])
    }

    @Test func readsALengthFromAHeader() {
        #expect(DaemonWire.payloadLength(header: Data([0, 0, 1, 0])) == 256)
        #expect(DaemonWire.payloadLength(header: Data([0, 0])) == nil)
    }

    @Test func refusesAHeaderAnnouncingMoreThanAFrameMayCarry() {
        #expect(DaemonWire.payloadLength(header: Data([0xFF, 0xFF, 0xFF, 0xFF])) == nil)
    }

    @Test func helloIsFramedJSONNamingTheVersionsAndTheClient() throws {
        let hello = DaemonWire.hello(client: "Herder 1.0")
        let length = try #require(DaemonWire.payloadLength(header: hello.prefix(DaemonWire.headerSize)))
        let body = hello.dropFirst(DaemonWire.headerSize)

        #expect(body.count == length)
        #expect(String(decoding: body, as: UTF8.self)
            == #"{"client":"Herder 1.0","max_protocol":1,"min_protocol":1,"type":"hello"}"#)
    }

    @Test func aWelcomeIsConnected() {
        let status = DaemonWire.status(fromReply: json(
            #"{"type":"welcome","protocol":1,"daemon_version":"0.1.0","host":"local"}"#
        ))

        #expect(status == .connected(DaemonInfo(daemonVersion: "0.1.0", protocolVersion: 1, host: "local")))
    }

    @Test func anIncompatibleReplyKeepsBothRangesToShow() {
        let status = DaemonWire.status(fromReply: json(
            #"{"type":"incompatible","min_protocol":4,"max_protocol":6,"daemon_version":"2.0.0"}"#
        ))

        #expect(status == .incompatible(daemonVersion: "2.0.0", supports: 4...6, app: DaemonWire.supported))
    }

    @Test func aWelcomeToAVersionTheAppDoesNotSpeakIsNotConnected() {
        let status = DaemonWire.status(fromReply: json(
            #"{"type":"welcome","protocol":9,"daemon_version":"2.0.0","host":"local"}"#
        ))

        guard case .unavailable = status else {
            Issue.record("expected unavailable, got \(status)")
            return
        }
    }

    @Test(arguments: [
        "not json",
        #"{"type":"welcome"}"#,
        #"{"type":"mystery","daemon_version":"1"}"#,
        #"{"type":"incompatible","min_protocol":6,"max_protocol":4,"daemon_version":"1"}"#,
    ])
    func anythingElseIsUnavailable(reply: String) {
        guard case .unavailable = DaemonWire.status(fromReply: json(reply)) else {
            Issue.record("expected unavailable for \(reply)")
            return
        }
    }
}
