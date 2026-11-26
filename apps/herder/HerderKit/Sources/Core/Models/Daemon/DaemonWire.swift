import Foundation

/// The bytes of herderd's protocol, with no I/O: what a frame looks like, the
/// first message and how to read the answer. The packages/herderd crate is the
/// other half, and `protocol.rs` there says what the messages mean.
public enum DaemonWire {
    /// The versions this build of the app speaks. Raise `supported.upperBound`
    /// when the app starts using a message the daemon gained in that version.
    public static let supported = 6...6

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

    /// Whether an `incompatible` reply comes from a daemon the app may end and
    /// replace with the one it bundles: one older than every version the app
    /// speaks, that owns no sessions. A newer daemon is left alone, because a
    /// newer app may be holding it, and so is any daemon with sessions,
    /// because ending it would end them. A daemon that does not report its
    /// sessions speaks only protocol 1, which had none.
    public static func mayReplace(afterReply payload: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              object["type"] as? String == "incompatible",
              let high = object["max_protocol"] as? Int,
              high < supported.lowerBound
        else { return false }
        switch object["sessions"] {
        case let sessions as Int: return sessions == 0
        case nil: return high <= 1
        default: return false
        }
    }

    // MARK: - GitHub

    /// Hands the daemon the access token to use. It answers with
    /// ``gitHubCheck(fromReply:id:)``, after asking GitHub whether it works.
    public static func setGitHubToken(id: Int, token: String) -> Data {
        message(["type": "set_github_token", "id": id, "token": token])
    }

    /// Makes the daemon forget its token.
    public static func clearGitHubToken(id: Int) -> Data {
        message(["type": "clear_github_token", "id": id])
    }

    /// Asks whether the token the daemon holds works.
    public static func checkGitHub(id: Int) -> Data {
        message(["type": "check_github", "id": id])
    }

    /// What a `github_response` to request `id` says. Anything else, including
    /// the answer to another request, is an error rather than a guess.
    public static func gitHubCheck(fromReply payload: Data, id: Int) -> GitHubCheck {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              object["type"] as? String == "github_response",
              object["id"] as? Int == id,
              let check = object["check"] as? [String: Any]
        else { return .error("Unrecognised reply from herderd.") }

        switch check["state"] as? String {
        case "not_connected": return .notConnected
        case "unauthorized": return .unauthorized
        case "ok":
            guard let login = check["login"] as? String else { break }
            return .ok(login: login)
        case "error":
            return .error(check["message"] as? String ?? "GitHub could not be asked.")
        default: break
        }
        return .error("Unrecognised reply from herderd.")
    }

    // MARK: - Pull requests

    /// Asks for the newest pull request of each branch in `repos`, which
    /// ``pullRequests(fromReply:id:)`` reads the answer to.
    public static func pullRequestQuery(id: Int, repos: [PullRequestQuery]) -> Data {
        message([
            "type": "pull_request_query",
            "id": id,
            "repos": repos.map { ["path": $0.path, "branches": $0.branches] as [String: Any] },
        ])
    }

    /// What a `pull_request_response` to request `id` says. `nil` for anything
    /// else, including the answer to another request, which is not one to guess
    /// from.
    public static func pullRequests(fromReply payload: Data, id: Int) -> PullRequestReply? {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              object["type"] as? String == "pull_request_response",
              object["id"] as? Int == id,
              let records = object["repos"] as? [[String: Any]],
              let seconds = object["next_poll_seconds"] as? Int
        else { return nil }

        var repositories: [PullRequestReply.Repository] = []
        for record in records {
            guard let path = record["path"] as? String,
                  let name = record["repository"] as? String,
                  let status = record["status"] as? [String: Any],
                  let parsed = pullRequestStatus(fromRecord: status),
                  let branches = record["branches"] as? [[String: Any]]
            else { return nil }

            var found: [String: LinkedPullRequest?] = [:]
            for entry in branches {
                guard let branch = entry["branch"] as? String else { return nil }
                switch entry["pull_request"] {
                case nil, is NSNull:
                    found[branch] = .some(nil)
                case let record as [String: Any]:
                    guard let pullRequest = linkedPullRequest(fromRecord: record) else { return nil }
                    found[branch] = .some(pullRequest)
                default:
                    return nil
                }
            }
            repositories.append(PullRequestReply.Repository(
                path: path,
                name: name,
                status: parsed,
                defaultBranch: record["default_branch"] as? String,
                branches: found
            ))
        }
        return PullRequestReply(repositories: repositories, nextPoll: .seconds(max(1, seconds)))
    }

    private static func pullRequestStatus(fromRecord record: [String: Any]) -> PullRequestReply.Status? {
        switch record["state"] as? String {
        case "ok": .ok
        case "not_accessible": .notAccessible
        case "unauthorized": .unauthorized
        case "error": .error(record["message"] as? String ?? "GitHub could not be asked.")
        default: nil
        }
    }

    private static func linkedPullRequest(fromRecord record: [String: Any]) -> LinkedPullRequest? {
        guard let number = record["number"] as? Int,
              let url = (record["url"] as? String).flatMap(URL.init(string:)),
              let title = record["title"] as? String,
              let state = record["state"] as? String,
              let updated = (record["updated_at"] as? String).flatMap(timestamp)
        else { return nil }
        return LinkedPullRequest(
            number: number,
            url: url,
            title: title,
            // A state this build does not know reads as `unknown`.
            state: LinkedPullRequest.State(rawValue: state) ?? .unknown,
            isDraft: record["is_draft"] as? Bool ?? false,
            mergedAt: (record["merged_at"] as? String).flatMap(timestamp),
            updatedAt: updated
        )
    }

    /// GitHub's timestamps: ISO 8601 to the second, in UTC.
    private static func timestamp(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601)
    }

    private static func message(_ fields: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }

    // MARK: - Issues

    /// Asks for the open issues of the repository `path`'s `origin` names,
    /// which ``issueList(fromReply:id:)`` reads the answer to.
    public static func issueQuery(
        id: Int, path: String, tab: GitHubIssueTab, freshness: GitHubIssueFreshness
    ) -> Data {
        message([
            "type": "issue_query", "id": id, "path": path, "tab": tab.rawValue, "freshness": freshness.rawValue,
        ])
    }

    /// Asks for one issue with its body and comments, which
    /// ``issueDetail(fromReply:id:)`` reads the answer to.
    public static func issueDetail(id: Int, path: String, number: Int) -> Data {
        message(["type": "issue_detail", "id": id, "path": path, "number": number])
    }

    /// What an `issue_response` to request `id` says. `nil` for anything else,
    /// including the answer to another request.
    public static func issueList(fromReply payload: Data, id: Int) -> GitHubIssueList? {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              object["type"] as? String == "issue_response",
              object["id"] as? Int == id,
              let result = object["result"] as? [String: Any],
              let status = (result["status"] as? [String: Any]).flatMap(issueStatus),
              let records = result["issues"] as? [[String: Any]]
        else { return nil }

        var issues: [GitHubIssue] = []
        for record in records {
            guard let issue = githubIssue(fromRecord: record) else { return nil }
            issues.append(issue)
        }
        return GitHubIssueList(
            repository: result["repository"] as? String,
            status: status,
            issues: issues,
            fetchedAt: (result["fetched_at"] as? Double).map { Date(timeIntervalSince1970: $0) },
            assignedCount: result["assigned_count"] as? Int,
            openCount: result["open_count"] as? Int
        )
    }

    /// What an `issue_detail_response` to request `id` says. `nil` for
    /// anything else.
    public static func issueDetail(fromReply payload: Data, id: Int) -> GitHubIssueDetailReply? {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              object["type"] as? String == "issue_detail_response",
              object["id"] as? Int == id,
              let result = object["result"] as? [String: Any],
              let status = (result["status"] as? [String: Any]).flatMap(issueStatus)
        else { return nil }

        guard let record = result["detail"] as? [String: Any] else {
            return GitHubIssueDetailReply(status: status)
        }
        guard let issue = (record["issue"] as? [String: Any]).flatMap(githubIssue(fromRecord:)),
              let body = record["body"] as? String,
              let comments = record["comments"] as? [[String: Any]]
        else { return nil }
        var parsed: [GitHubIssueDetail.Comment] = []
        for comment in comments {
            guard let text = comment["body"] as? String else { return nil }
            parsed.append(GitHubIssueDetail.Comment(
                author: comment["author"] as? String,
                body: text,
                createdAt: (comment["created_at"] as? String).flatMap(timestamp) ?? .distantPast
            ))
        }
        return GitHubIssueDetailReply(
            status: status, detail: GitHubIssueDetail(issue: issue, body: body, comments: parsed)
        )
    }

    private static func issueStatus(fromRecord record: [String: Any]) -> GitHubIssueStatus? {
        switch record["state"] as? String {
        case "ok": .ok
        case "not_accessible": .notAccessible
        case "unauthorized": .unauthorized
        case "permission_missing": .permissionMissing
        case "error": .error(record["message"] as? String ?? "GitHub could not be asked.")
        default: nil
        }
    }

    private static func githubIssue(fromRecord record: [String: Any]) -> GitHubIssue? {
        guard let number = record["number"] as? Int,
              let url = (record["url"] as? String).flatMap(URL.init(string:)),
              let title = record["title"] as? String
        else { return nil }
        let labels = (record["labels"] as? [[String: Any]] ?? []).compactMap { label -> GitHubIssue.Label? in
            guard let name = label["name"] as? String else { return nil }
            return GitHubIssue.Label(name: name, color: label["color"] as? String ?? "")
        }
        return GitHubIssue(
            number: number,
            url: url,
            title: title,
            labels: labels,
            author: record["author"] as? String,
            createdAt: (record["created_at"] as? String).flatMap(timestamp) ?? .distantPast,
            updatedAt: (record["updated_at"] as? String).flatMap(timestamp) ?? .distantPast,
            commentCount: record["comments"] as? Int ?? 0
        )
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

    public static func fetchedBase(fromResult result: [String: Any]) -> String?? {
        nullable(result, "base") { $0 as? String }
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
