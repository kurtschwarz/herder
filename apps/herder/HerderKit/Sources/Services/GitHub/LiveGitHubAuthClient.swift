import Core
import Foundation

/// Signs in to GitHub with the device flow of the Herder GitHub App, and
/// refreshes what that gives, over `URLSession`. See ADR 0003.
///
/// A device flow needs only the app's client ID, which is public: there is no
/// client secret to ship. A build without one cannot sign in, and says so
/// rather than sending a request that is certain to fail.
public struct LiveGitHubAuthClient: GitHubAuthClient {
    private static let deviceGrant = "urn:ietf:params:oauth:grant-type:device_code"

    private let clientID: String
    private let session: URLSession
    private let baseURL: URL
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - clientID: the GitHub App's client ID. Empty when this build has none.
    ///   - baseURL: where GitHub's sign-in endpoints are. A test points it at a stub.
    ///   - now: the wall clock, which the expiries it returns are measured from.
    public init(
        clientID: String,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://github.com")!,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.clientID = clientID
        self.session = session
        self.baseURL = baseURL
        self.now = now
    }

    public func requestDeviceCode() async throws -> GitHubDeviceCode {
        let reply = try await post("login/device/code", ["client_id": try configuredClientID()])
        guard let deviceCode = reply["device_code"] as? String,
              let userCode = reply["user_code"] as? String,
              let address = reply["verification_uri"] as? String,
              let verificationURL = URL(string: address),
              let expiresIn = reply["expires_in"] as? Int
        else { throw Self.failure(in: reply, otherwise: "GitHub's answer to the sign-in request was not one Herder understands.") }

        return GitHubDeviceCode(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURL: verificationURL,
            expiresIn: .seconds(expiresIn),
            interval: .seconds(reply["interval"] as? Int ?? 5)
        )
    }

    public func poll(deviceCode: String) async throws -> GitHubDevicePoll {
        let reply = try await post("login/oauth/access_token", [
            "client_id": try configuredClientID(),
            "device_code": deviceCode,
            "grant_type": Self.deviceGrant,
        ])
        if reply["access_token"] != nil { return .signedIn(try tokens(in: reply)) }

        switch reply["error"] as? String {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown
        case "expired_token": return .expired
        case "access_denied": return .denied
        default: throw Self.failure(in: reply, otherwise: "GitHub's answer to the sign-in poll was not one Herder understands.")
        }
    }

    public func refresh(using refreshToken: String) async throws -> GitHubTokens {
        let reply = try await post("login/oauth/access_token", [
            "client_id": try configuredClientID(),
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
        if reply["access_token"] != nil { return try tokens(in: reply) }
        if reply["error"] as? String == "bad_refresh_token" { throw GitHubAuthError.refreshTokenRejected }
        throw Self.failure(in: reply, otherwise: "GitHub's answer to the token refresh was not one Herder understands.")
    }

    // MARK: - Reading answers

    private func configuredClientID() throws -> String {
        guard !clientID.isEmpty else { throw GitHubAuthError.notConfigured }
        return clientID
    }

    /// The tokens of a successful answer, with expiries counted from now.
    private func tokens(in reply: [String: Any]) throws -> GitHubTokens {
        guard let access = reply["access_token"] as? String,
              let refresh = reply["refresh_token"] as? String,
              let accessLifetime = reply["expires_in"] as? Int,
              let refreshLifetime = reply["refresh_token_expires_in"] as? Int
        else {
            throw GitHubAuthError.unexpected(
                "GitHub gave a token that does not expire. Turn on expiring user tokens for the GitHub App."
            )
        }
        let issued = now()
        return GitHubTokens(
            accessToken: access,
            refreshToken: refresh,
            accessExpiresAt: issued.addingTimeInterval(TimeInterval(accessLifetime)),
            refreshExpiresAt: issued.addingTimeInterval(TimeInterval(refreshLifetime))
        )
    }

    /// What GitHub said was wrong, from its own `error_description`, which
    /// never quotes a token.
    private static func failure(in reply: [String: Any], otherwise fallback: String) -> GitHubAuthError {
        .unexpected((reply["error_description"] as? String) ?? (reply["error"] as? String) ?? fallback)
    }

    // MARK: - Network

    /// A form POST that wants JSON back. GitHub answers sign-in errors with a
    /// 200 and an `error` field, so a status is only looked at when there is
    /// no JSON to read.
    private func post(_ path: String, _ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.form(fields).utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GitHubAuthError.network((error as? URLError)?.localizedDescription ?? error.localizedDescription)
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return object }
        let status = (response as? HTTPURLResponse)?.statusCode
        throw GitHubAuthError.network(status.map { "GitHub answered \($0)" } ?? "GitHub did not answer")
    }

    private static func form(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.sorted { $0.key < $1.key }.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
    }
}
