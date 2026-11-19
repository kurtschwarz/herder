import Foundation

/// The bytes of herderd's protocol, with no I/O: what a frame looks like, the
/// first message and how to read the answer. The packages/herderd crate is the
/// other half, and `protocol.rs` there says what the messages mean.
public enum DaemonWire {
    /// The versions this build of the app speaks. Raise `supported.upperBound`
    /// when the app starts using a message the daemon gained in that version.
    public static let supported = 2...2

    /// A frame is a big-endian `UInt32` length and then that many bytes.
    public static let headerSize = 4

    /// The most a frame may carry. The daemon refuses more.
    public static let maxFrame = 16 * 1024 * 1024

    public static func frame(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        return Data(bytes: &length, count: headerSize) + payload
    }

    /// The payload length a frame header announces, or `nil` if it is not a
    /// header or announces more than a frame may carry.
    public static func payloadLength(header: Data) -> Int? {
        guard header.count == headerSize else { return nil }
        let length = header.reduce(0) { ($0 << 8) | Int($1) }
        return length <= maxFrame ? length : nil
    }

    /// The first frame on every connection.
    public static func hello(client: String) -> Data {
        let message: [String: Any] = [
            "type": "hello",
            "min_protocol": supported.lowerBound,
            "max_protocol": supported.upperBound,
            "client": client,
        ]
        // Sorted, so what goes out is the same bytes every time.
        let payload = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        return frame(payload ?? Data())
    }

    /// What the daemon's answer to ``hello(client:)`` means for the app.
    public static func status(fromReply payload: Data) -> DaemonStatus {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let type = object["type"] as? String,
              let version = object["daemon_version"] as? String
        else { return .unavailable(reason: "Unrecognised reply from herderd.") }

        switch type {
        case "welcome":
            guard let negotiated = object["protocol"] as? Int, let host = object["host"] as? String else { break }
            guard supported.contains(negotiated) else {
                return .unavailable(reason: "herderd chose protocol \(negotiated), which this app does not speak.")
            }
            return .connected(DaemonInfo(daemonVersion: version, protocolVersion: negotiated, host: host))
        case "incompatible":
            guard let low = object["min_protocol"] as? Int, let high = object["max_protocol"] as? Int, low <= high
            else { break }
            return .incompatible(daemonVersion: version, supports: low...high, app: supported)
        default:
            break
        }
        return .unavailable(reason: "Unrecognised reply from herderd.")
    }

    // MARK: - Git

    /// The payload of a `git_request`: `op` and its arguments in one flat
    /// object beside the `id`. Paths are strings on the daemon's host.
    public static func gitRequest(id: Int, op: String, arguments: [String: String] = [:]) -> Data {
        var message: [String: Any] = ["type": "git_request", "id": id, "op": op]
        for (key, value) in arguments { message[key] = value }
        return (try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }

    /// The `result` of the `git_response` to request `id`. Throws what the
    /// daemon said when it answered with an `error`, and a failure of its own
    /// when the reply is not the answer to this request.
    public static func gitResult(fromReply payload: Data, id: Int) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              object["type"] as? String == "git_response",
              object["id"] as? Int == id
        else { throw GitClientError.commandFailed("Unrecognised reply from herderd.") }

        if let error = object["error"] as? [String: Any] {
            throw GitClientError.commandFailed(error["message"] as? String ?? "herderd could not run git.")
        }
        guard let result = object["result"] as? [String: Any] else {
            throw GitClientError.commandFailed("Unrecognised reply from herderd.")
        }
        return result
    }

    /// What a `repository_kind` result says.
    public static func repositoryKind(fromResult result: [String: Any]) -> GitRepositoryKind? {
        switch result["kind"] as? String {
        case "main_working_tree": .mainWorkingTree
        case "bare": .bare
        case "not_a_repository": .notARepository
        case "linked_worktree":
            (result["main_repository"] as? String).map { .linkedWorktree(mainRepository: folder($0)) }
        default: nil
        }
    }

    /// What a `worktrees` result lists, in the daemon's order.
    public static func worktrees(fromResult result: [String: Any]) -> [GitWorktree]? {
        guard let records = result["worktrees"] as? [[String: Any]] else { return nil }
        var worktrees: [GitWorktree] = []
        for record in records {
            guard let path = record["path"] as? String,
                  let checkout = checkout(fromRecord: record["checkout"]),
                  let isMain = record["is_main_working_tree"] as? Bool
            else { return nil }
            worktrees.append(GitWorktree(
                path: folder(path),
                checkout: checkout,
                isMainWorkingTree: isMain,
                lastActivity: (record["last_activity"] as? Double).map(Date.init(timeIntervalSince1970:))
            ))
        }
        return worktrees
    }

    public static func branches(fromResult result: [String: Any]) -> [String]? {
        result["branches"] as? [String]
    }

    /// The folder a `git_directory` result names. `.some(nil)` is the daemon
    /// saying there is none; `nil` is a reply that is not an answer.
    public static func gitDirectory(fromResult result: [String: Any]) -> URL?? {
        guard result.keys.contains("path") else { return .none }
        guard let path = result["path"] as? String else { return .some(nil) }
        // No trailing slash, as the app built it when it appended `.git` itself.
        return .some(URL(filePath: path, directoryHint: .notDirectory).resolvingSymlinksInPath())
    }

    public static func checkout(fromResult result: [String: Any]) -> GitWorktree.Checkout?? {
        guard result.keys.contains("checkout") else { return .none }
        guard let record = result["checkout"], !(record is NSNull) else { return .some(nil) }
        return checkout(fromRecord: record).map { .some($0) }
    }

    private static func checkout(fromRecord record: Any?) -> GitWorktree.Checkout? {
        guard let record = record as? [String: Any] else { return nil }
        switch record["type"] as? String {
        case "branch": return (record["name"] as? String).map { .branch($0) }
        case "detached": return (record["sha"] as? String).map { .detached(sha: $0) }
        default: return nil
        }
    }

    /// A path from the daemon as a URL, resolved the way every other URL the
    /// app keeps is, so the two spell a folder the same way when compared.
    private static func folder(_ path: String) -> URL {
        URL(filePath: path, directoryHint: .isDirectory).resolvingSymlinksInPath()
    }
}
