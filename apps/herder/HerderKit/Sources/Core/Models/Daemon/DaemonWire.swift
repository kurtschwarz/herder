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
    public static func gitRequest(id: Int, op: String, arguments: [String: Any] = [:]) -> Data {
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

    /// What a `status` result says about each path, which it gives relative to
    /// the working tree whose key is `root`.
    public static func status(fromResult result: [String: Any], root: PathKey) -> GitWorktreeStatus? {
        guard let records = result["entries"] as? [[String: Any]] else { return nil }
        var entries: [PathKey: GitStatus] = [:]
        for record in records {
            guard let path = record["path"] as? String,
                  let status = record["status"] as? [String: Any],
                  let value = gitStatus(fromRecord: status)
            else { return nil }
            entries[root.appending(path)] = value
        }
        return GitWorktreeStatus(root: root, entries: entries)
    }

    private static func gitStatus(fromRecord record: [String: Any]) -> GitStatus? {
        switch record["type"] as? String {
        case "untracked": return .untracked
        case "ignored": return .ignored
        case "unmerged": return .unmerged
        case "tracked":
            guard let staged = (record["staged"] as? String).flatMap(change),
                  let unstaged = (record["unstaged"] as? String).flatMap(change)
            else { return nil }
            return .tracked(staged: staged, unstaged: unstaged)
        default: return nil
        }
    }

    private static func change(_ name: String) -> GitChange? {
        switch name {
        case "unchanged": .unchanged
        case "added": .added
        case "modified": .modified
        case "deleted": .deleted
        case "renamed": .renamed
        case "copied": .copied
        case "type_changed": .typeChanged
        default: nil
        }
    }

    /// What `summary` holds. `.some(nil)` is the daemon saying there is none.
    public static func changeSummary(fromResult result: [String: Any]) -> GitChangeSummary?? {
        nullable(result, "summary") { value in
            guard let record = value as? [String: Any],
                  let insertions = record["insertions"] as? Int,
                  let deletions = record["deletions"] as? Int
            else { return nil }
            return GitChangeSummary(insertions: insertions, deletions: deletions)
        }
    }

    public static func mergeBase(fromResult result: [String: Any]) -> String?? {
        nullable(result, "sha") { $0 as? String }
    }

    public static func upstream(fromResult result: [String: Any]) -> String?? {
        nullable(result, "upstream") { $0 as? String }
    }

    public static func contents(fromResult result: [String: Any]) -> String?? {
        nullable(result, "text") { $0 as? String }
    }

    public static func commit(fromResult result: [String: Any]) -> GitCommit?? {
        nullable(result, "commit") { commit(fromRecord: $0) }
    }

    public static func commits(fromResult result: [String: Any]) -> [GitCommit]? {
        guard let records = result["commits"] as? [Any] else { return nil }
        let commits = records.compactMap { commit(fromRecord: $0) }
        return commits.count == records.count ? commits : nil
    }

    public static func refs(fromResult result: [String: Any]) -> [GitRef]? {
        guard let records = result["refs"] as? [[String: Any]] else { return nil }
        var refs: [GitRef] = []
        for record in records {
            guard let name = record["name"] as? String,
                  let date = record["date"] as? Double,
                  let kind = (record["kind"] as? String).flatMap(refKind)
            else { return nil }
            refs.append(GitRef(name: name, kind: kind, date: Date(timeIntervalSince1970: date)))
        }
        return refs
    }

    public static func changedFiles(fromResult result: [String: Any]) -> [GitChangedFile]? {
        guard let records = result["files"] as? [[String: Any]] else { return nil }
        var files: [GitChangedFile] = []
        for record in records {
            guard let path = record["path"] as? String,
                  let status = (record["status"] as? String).flatMap(fileStatus),
                  let insertions = record["insertions"] as? Int,
                  let deletions = record["deletions"] as? Int
            else { return nil }
            files.append(GitChangedFile(
                path: path,
                previousPath: record["previous_path"] as? String,
                status: status,
                insertions: insertions,
                deletions: deletions
            ))
        }
        return files
    }

    private static func commit(fromRecord record: Any) -> GitCommit? {
        guard let record = record as? [String: Any],
              let sha = record["sha"] as? String,
              let subject = record["subject"] as? String,
              let date = record["date"] as? Double
        else { return nil }
        return GitCommit(sha: sha, subject: subject, date: Date(timeIntervalSince1970: date))
    }

    private static func refKind(_ name: String) -> GitRef.Kind? {
        switch name {
        case "branch": .branch
        case "remote_branch": .remoteBranch
        case "tag": .tag
        default: nil
        }
    }

    private static func fileStatus(_ name: String) -> GitChangedFile.Status? {
        switch name {
        case "modified": .modified
        case "added": .added
        case "deleted": .deleted
        case "renamed": .renamed
        default: nil
        }
    }

    /// `.some(nil)` for a `null`, `nil` for a key that is missing or unreadable.
    private static func nullable<T>(_ result: [String: Any], _ key: String, _ read: (Any) -> T?) -> T?? {
        guard let value = result[key] else { return .none }
        if value is NSNull { return .some(nil) }
        return read(value).map { .some($0) }
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
