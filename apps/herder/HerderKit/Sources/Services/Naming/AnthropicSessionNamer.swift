import Core
import Foundation

/// ``SessionNamer`` over `POST {endpoint}/v1/messages`, asking Haiku for the
/// kind of change, a branch slug and a title.
///
/// Speaks the plain Messages API, so Meridian's local endpoint and
/// `api.anthropic.com` both answer it. The answer is JSON in the reply's text
/// rather than a forced tool call, which is what a proxy over a coding agent
/// is most likely to get right.
public struct AnthropicSessionNamer: SessionNamer {
    public static let model = "claude-haiku-5-5"

    public enum Failure: Error, Equatable {
        case status(Int)
        case unreadable
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    static let instructions = """
        You name a unit of software work for a git branch and a session list. Reply with one JSON \
        object and nothing else: {"type": "feat" | "fix" | "chore", "slug": "...", "title": "..."}. \
        "type" is feat for new behavior, fix for a bug, chore for anything else. "slug" is lowercase \
        kebab-case, at most 5 words. "title" is a short plain-language title, at most 6 words.
        """

    public func name(for prompt: String, using configuration: NamingConfiguration) async throws -> SessionName {
        var request = URLRequest(url: configuration.endpoint.appending(path: "v1/messages"))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if let key = configuration.apiKey { request.setValue(key, forHTTPHeaderField: "x-api-key") }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Self.model,
            "max_tokens": 200,
            "system": Self.instructions,
            "messages": [["role": "user", "content": prompt]],
        ] as [String: Any])

        let (data, response) = try await session.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw Failure.status(status)
        }
        return try Self.parse(reply: data)
    }

    /// The name in the text of a Messages API reply. Tolerates the JSON being
    /// wrapped in a code fence or a sentence.
    static func parse(reply: Data) throws -> SessionName {
        guard let body = try JSONSerialization.jsonObject(with: reply) as? [String: Any],
              let content = body["content"] as? [[String: Any]],
              let text = content.compactMap({ $0["text"] as? String }).first,
              let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
              let object = try JSONSerialization.jsonObject(with: Data(text[open...close].utf8)) as? [String: Any],
              let rawType = object["type"] as? String, let type = OrderBranchType(rawValue: rawType),
              let slug = object["slug"] as? String,
              let title = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { throw Failure.unreadable }
        return SessionName(type: type, slug: slug, title: title)
    }
}
