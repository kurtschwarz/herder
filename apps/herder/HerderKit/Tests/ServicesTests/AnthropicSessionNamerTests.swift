import Core
import Foundation
@testable import Services
import Testing

/// Answers every request a session makes with what the test set, and keeps the
/// request to be looked at.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var seen: URLRequest?
    nonisolated(unsafe) static var seenBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.seen = request
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            Self.seenBody = data
        } else {
            Self.seenBody = request.httpBody
        }
        let (status, body) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct AnthropicSessionNamerTests {
    let namer: AnthropicSessionNamer

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        namer = AnthropicSessionNamer(session: URLSession(configuration: configuration))
        StubURLProtocol.seen = nil
        StubURLProtocol.seenBody = nil
    }

    private func reply(_ text: String) -> Data {
        let body: [String: Any] = ["content": [["type": "text", "text": text]]]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    private let configuration = NamingConfiguration(endpoint: URL(string: "http://127.0.0.1:3456")!, apiKey: "sk-x")

    @Test func askingHaikuPostsTheMessagesApiAndReadsTheName() async throws {
        StubURLProtocol.handler = { _ in
            (200, reply(#"{"type":"fix","slug":"crash-on-save","title":"Fix crash on save"}"#))
        }

        let name = try await namer.name(for: "it crashes when I save", using: configuration)

        #expect(name == SessionName(type: .fix, slug: "crash-on-save", title: "Fix crash on save"))
        let request = try #require(StubURLProtocol.seen)
        #expect(request.url?.absoluteString == "http://127.0.0.1:3456/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-x")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let sent = try #require(StubURLProtocol.seenBody)
        let body = try #require(JSONSerialization.jsonObject(with: sent) as? [String: Any])
        #expect(body["model"] as? String == "claude-haiku-5-5")
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [["role": "user", "content": "it crashes when I save"]])
    }

    @Test func noKeyMeansNoKeyHeader() async throws {
        StubURLProtocol.handler = { _ in (200, reply(#"{"type":"feat","slug":"x","title":"X"}"#)) }

        _ = try await namer.name(for: "x", using: NamingConfiguration(endpoint: configuration.endpoint))

        #expect(StubURLProtocol.seen?.value(forHTTPHeaderField: "x-api-key") == nil)
    }

    @Test func aNameWrappedInAFenceOrASentenceIsStillRead() async throws {
        StubURLProtocol.handler = { _ in
            (200, reply("Here you go:\n```json\n{\"type\":\"chore\",\"slug\":\"bump-deps\",\"title\":\"Bump deps\"}\n```"))
        }

        #expect(try await namer.name(for: "x", using: configuration).slug == "bump-deps")
    }

    @Test func aRefusalIsAnError() async {
        StubURLProtocol.handler = { _ in (401, Data("{}".utf8)) }

        await #expect(throws: AnthropicSessionNamer.Failure.status(401)) {
            try await namer.name(for: "x", using: configuration)
        }
    }

    @Test func anAnswerThatIsNotANameIsAnError() async {
        for text in ["no json here", #"{"type":"docs","slug":"x","title":"X"}"#, #"{"type":"feat","slug":"x","title":" "}"#] {
            StubURLProtocol.handler = { _ in (200, reply(text)) }
            await #expect(throws: AnthropicSessionNamer.Failure.unreadable) {
                try await namer.name(for: "x", using: configuration)
            }
        }
    }
}
