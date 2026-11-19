import Core
import Foundation
import Synchronization
@testable import Services
import Testing

/// What a stubbed `URLSession` was asked and what it answers.
final class StubGitHub: URLProtocol, @unchecked Sendable {
    struct Sent: Equatable {
        var path: String
        var accept: String?
        var form: [String: String]
    }

    private struct Route {
        var status: Int
        var body: String
        var failure: URLError?
        var sent: [Sent] = []
    }

    /// Keyed by host, so each test has a server of its own.
    private static let routes = Mutex<[String: Route]>([:])

    static func serve(host: String, status: Int = 200, body: String = "{}", failure: URLError? = nil) {
        routes.withLock { $0[host] = Route(status: status, body: body, failure: failure) }
    }

    static func sent(to host: String) -> [Sent] { routes.withLock { $0[host]?.sent ?? [] } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubGitHub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let host = url.host else { return }
        let sent = Sent(
            path: url.path(percentEncoded: false),
            accept: request.value(forHTTPHeaderField: "Accept"),
            form: Self.fields(in: Self.body(of: request))
        )
        let route = Self.routes.withLock { routes -> Route? in
            routes[host]?.sent.append(sent)
            return routes[host]
        }
        guard let route else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        if let failure = route.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: route.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(route.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func body(of request: URLRequest) -> String {
        if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func fields(in body: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: body.split(separator: "&").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1].removingPercentEncoding ?? parts[1])
        })
    }
}

@Suite(.timeLimit(.minutes(1))) struct LiveGitHubAuthClientTests {
    let host = "github-\(UUID().uuidString.prefix(8).lowercased()).test"
    let issued = Date(timeIntervalSince1970: 1_700_000_000)

    func client(clientID: String = "Iv1.herder") -> LiveGitHubAuthClient {
        LiveGitHubAuthClient(
            clientID: clientID, session: StubGitHub.session(),
            baseURL: URL(string: "https://\(host)")!, now: { [issued] in issued }
        )
    }

    static let tokenReply = """
        {"access_token":"ghu_access","expires_in":28800,"refresh_token":"ghr_refresh",\
        "refresh_token_expires_in":15897600,"token_type":"bearer","scope":""}
        """

    // MARK: - Starting

    @Test func startingAFlowAsksForACodeForTheClient() async throws {
        StubGitHub.serve(host: host, body: """
            {"device_code":"dc","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device",\
            "expires_in":900,"interval":5}
            """)

        let code = try await client().requestDeviceCode()

        #expect(code == GitHubDeviceCode(
            deviceCode: "dc", userCode: "WDJB-MJHT",
            verificationURL: URL(string: "https://github.com/login/device")!,
            expiresIn: .seconds(900), interval: .seconds(5)
        ))
        #expect(StubGitHub.sent(to: host) == [
            .init(path: "/login/device/code", accept: "application/json", form: ["client_id": "Iv1.herder"])
        ])
    }

    @Test func aBuildWithoutAClientIDSendsNothing() async {
        StubGitHub.serve(host: host)

        await #expect(throws: GitHubAuthError.notConfigured) { try await client(clientID: "").requestDeviceCode() }
        await #expect(throws: GitHubAuthError.notConfigured) { try await client(clientID: "").poll(deviceCode: "dc") }
        await #expect(throws: GitHubAuthError.notConfigured) { try await client(clientID: "").refresh(using: "r") }
        #expect(StubGitHub.sent(to: host).isEmpty)
    }

    @Test func aDisabledDeviceFlowSaysWhatGitHubSaid() async {
        StubGitHub.serve(host: host, body: #"{"error":"device_flow_disabled","error_description":"Device flow must be enabled"}"#)

        await #expect(throws: GitHubAuthError.unexpected("Device flow must be enabled")) {
            try await client().requestDeviceCode()
        }
    }

    // MARK: - Polling

    @Test func aPollSendsTheDeviceGrant() async throws {
        StubGitHub.serve(host: host, body: #"{"error":"authorization_pending"}"#)

        _ = try await client().poll(deviceCode: "dc")

        #expect(StubGitHub.sent(to: host) == [
            .init(path: "/login/oauth/access_token", accept: "application/json", form: [
                "client_id": "Iv1.herder", "device_code": "dc",
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
        ])
    }

    @Test(arguments: [
        (#"{"error":"authorization_pending"}"#, GitHubDevicePoll.pending),
        (#"{"error":"slow_down","interval":10}"#, .slowDown),
        (#"{"error":"expired_token"}"#, .expired),
        (#"{"error":"access_denied"}"#, .denied),
    ])
    func eachAnswerToAPollIsOneOutcome(body: String, expected: GitHubDevicePoll) async throws {
        StubGitHub.serve(host: host, body: body)

        #expect(try await client().poll(deviceCode: "dc") == expected)
    }

    @Test func aFinishedFlowGivesTokensThatExpireFromNow() async throws {
        StubGitHub.serve(host: host, body: Self.tokenReply)

        let poll = try await client().poll(deviceCode: "dc")

        #expect(poll == .signedIn(GitHubTokens(
            accessToken: "ghu_access", refreshToken: "ghr_refresh",
            accessExpiresAt: issued.addingTimeInterval(28800),
            refreshExpiresAt: issued.addingTimeInterval(15_897_600)
        )))
    }

    @Test func aTokenThatNeverExpiresIsRefusedWithAnExplanation() async {
        StubGitHub.serve(host: host, body: #"{"access_token":"ghu_access","token_type":"bearer"}"#)

        await #expect(throws: GitHubAuthError.self) { try await client().poll(deviceCode: "dc") }
    }

    @Test func anUnknownErrorIsReportedAsGitHubSaidIt() async {
        StubGitHub.serve(host: host, body: #"{"error":"incorrect_client_credentials","error_description":"The client_id is not valid"}"#)

        await #expect(throws: GitHubAuthError.unexpected("The client_id is not valid")) {
            try await client().poll(deviceCode: "dc")
        }
    }

    // MARK: - Refreshing

    @Test func aRefreshTradesTheRefreshTokenForANewPair() async throws {
        StubGitHub.serve(host: host, body: Self.tokenReply)

        let tokens = try await client().refresh(using: "ghr_old")

        #expect(tokens.accessToken == "ghu_access")
        #expect(tokens.refreshToken == "ghr_refresh")
        #expect(StubGitHub.sent(to: host) == [
            .init(path: "/login/oauth/access_token", accept: "application/json", form: [
                "client_id": "Iv1.herder", "grant_type": "refresh_token", "refresh_token": "ghr_old",
            ])
        ])
    }

    @Test func aRefreshTokenGitHubRejectsIsSaidSo() async {
        StubGitHub.serve(host: host, body: #"{"error":"bad_refresh_token","error_description":"The refresh token passed is incorrect or expired."}"#)

        await #expect(throws: GitHubAuthError.refreshTokenRejected) { try await client().refresh(using: "ghr_old") }
    }

    // MARK: - Failures

    @Test func aNetworkFailureIsANetworkError() async {
        StubGitHub.serve(host: host, failure: URLError(.notConnectedToInternet))

        do {
            _ = try await client().refresh(using: "ghr_old")
            Issue.record("expected a network error")
        } catch GitHubAuthError.network {
        } catch {
            Issue.record("expected a network error, got \(error)")
        }
    }

    @Test func aServerErrorWithNoJSONIsANetworkErrorNamingTheStatus() async {
        StubGitHub.serve(host: host, status: 502, body: "<html>Bad gateway</html>")

        await #expect(throws: GitHubAuthError.network("GitHub answered 502")) { try await client().poll(deviceCode: "dc") }
    }
}
