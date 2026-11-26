import Core
import Foundation
import Observation

/// The "From issue" modal's state: the open issues of one repository, in two
/// tabs, and picking one to start an agent from.
///
/// Opening asks herderd twice for the first tab, together: from memory, which
/// shows at once if herderd has it, and fresh from GitHub, which replaces it.
/// After that only the refresh button asks, and only for the tab on show. A
/// failed refresh keeps the rows and says so in a line below them; with no rows
/// to keep, the modal shows what is wrong in their place. See ADR 0005.
///
/// Starting asks for the issue's body and comments, fresh, and stops there if
/// that fails: an agent is never started from a title alone. Cutting the
/// worktree is not this model's business, which is why it hands back the detail.
@Observable
final class IssueListModel {
    /// Why there is no list to show, and so what the modal offers instead.
    enum Unavailable: Equatable {
        case notSignedIn
        /// The GitHub App is not installed on `owner/name`.
        case notInstalled(String)
        /// The installation on `owner/name` has not approved reading issues.
        case permissionMissing(String)
        case failed(String)
    }

    /// What picking an issue comes to.
    enum Outcome: Equatable {
        /// A session for it is already open: show that one.
        case resume(AgentSession)
        /// Start a new one from this.
        case start(GitHubIssueDetail)
    }

    private struct Loaded {
        var issues: [GitHubIssue]
        var fetchedAt: Date
    }

    /// What the workspace is called, for the modal's heading.
    let workspaceName: String

    private let path: String
    private let client: any GitHubIssuesClient
    private let openSession: (Int) -> AgentSession?
    private let signInRefused: () async -> Void
    private let now: () -> Date

    /// What was typed. A bare `#123` or an issue's link jumps to that issue.
    var query = "" {
        didSet { if query != oldValue { queryChanged() } }
    }

    private(set) var tab: GitHubIssueTab = .assigned
    private(set) var unavailable: Unavailable?

    /// A refresh that failed while there were rows to keep, in one line.
    private(set) var refreshError: String?

    /// What went wrong starting, which also means nothing started.
    private(set) var failure: String?

    private(set) var isStarting = false
    private(set) var isLookingUp = false

    /// `owner/name`, once herderd has said.
    private(set) var repository: String?

    private(set) var assignedCount: Int?
    private(set) var openCount: Int?

    /// Fresh requests in flight, so the refresh button spins while any is.
    private var freshInFlight = 0
    private var lists: [GitHubIssueTab: Loaded] = [:]
    private var freshArrived: Set<GitHubIssueTab> = []
    private var userChoseTab = false
    private var retriedSignIn = false

    /// The one selected by hand. See ``selected``.
    private var picked: Int?
    private var lookedUp: GitHubIssue?
    private var lookup: Task<Void, Never>?

    /// - Parameters:
    ///   - openSession: the session for an issue that has not ended, if any.
    ///   - signInRefused: what to do when GitHub refuses the token: try to
    ///     refresh it, and ask for a reconnect if that fails.
    init(
        workspaceName: String,
        path: String,
        client: any GitHubIssuesClient,
        openSession: @escaping (Int) -> AgentSession?,
        signInRefused: @escaping () async -> Void = {},
        now: @escaping () -> Date = { .now }
    ) {
        self.workspaceName = workspaceName
        self.path = path
        self.client = client
        self.openSession = openSession
        self.signInRefused = signInRefused
        self.now = now
    }

    // MARK: - Loading

    /// Fills the first tab: from herderd's memory and from GitHub at once.
    /// When nothing is assigned to the user and they have not chosen a tab,
    /// goes on to "All open".
    func load() async {
        unavailable = nil
        refreshError = nil
        retriedSignIn = false
        await fetchBoth(tab)
        if !userChoseTab, tab == .assigned, assignedCount == 0 { await switchTo(.open) }
    }

    /// Asks GitHub again for the tab on show, and only that.
    func refresh() async {
        refreshError = nil
        await fetch(tab, .fresh)
    }

    /// Whether a request to GitHub is in flight.
    var isRefreshing: Bool { freshInFlight > 0 }

    /// Whether there is nothing to show yet: no rows, and no reason why.
    var isLoading: Bool { lists[tab] == nil && unavailable == nil }

    private func fetchBoth(_ tab: GitHubIssueTab) async {
        async let cached: Void = fetch(tab, .cached)
        async let fresh: Void = fetch(tab, .fresh)
        _ = await (cached, fresh)
    }

    private func fetch(_ tab: GitHubIssueTab, _ freshness: GitHubIssueFreshness) async {
        if freshness == .fresh { freshInFlight += 1 }
        defer { if freshness == .fresh { freshInFlight -= 1 } }

        var reply: GitHubIssueList
        do {
            reply = try await client.list(at: path, tab: tab, freshness: freshness)
            if freshness == .fresh, reply.status == .unauthorized, !retriedSignIn {
                // Once: refresh the token or ask to reconnect, then look again.
                retriedSignIn = true
                await signInRefused()
                reply = try await client.list(at: path, tab: tab, freshness: freshness)
            }
        } catch {
            reply = GitHubIssueList(repository: repository, status: .error("herderd could not be reached."))
        }
        apply(reply, to: tab, freshness)
    }

    private func apply(_ reply: GitHubIssueList, to tab: GitHubIssueTab, _ freshness: GitHubIssueFreshness) {
        let fresh = freshness == .fresh
        if let name = reply.repository { repository = name }

        switch reply.status {
        case .ok:
            // Nothing remembered, or something older than what is shown.
            guard let fetchedAt = reply.fetchedAt, fresh || !freshArrived.contains(tab) else { return }
            if fresh { freshArrived.insert(tab) }
            lists[tab] = Loaded(issues: reply.issues, fetchedAt: fetchedAt)
            if let count = reply.assignedCount { assignedCount = count }
            if let count = reply.openCount { openCount = count }
            unavailable = nil
            refreshError = nil

        // What only GitHub can say: memory has nothing to say about these.
        case _ where !fresh:
            return
        case .unauthorized:
            unavailable = .notSignedIn
        case .notAccessible:
            unavailable = .notInstalled(reply.repository ?? repository ?? workspaceName)
        case .permissionMissing:
            unavailable = .permissionMissing(reply.repository ?? repository ?? workspaceName)
        case .error(let message):
            // The rows stay, and the line below them says why they are old.
            if lists[tab] != nil {
                refreshError = message
            } else {
                unavailable = .failed(message)
            }
        }
    }

    // MARK: - Tabs

    func count(for tab: GitHubIssueTab) -> Int? {
        switch tab {
        case .assigned: assignedCount
        case .open: openCount
        }
    }

    /// Shows `tab`, asking for it if it has not been asked for yet. It is
    /// never asked for again by showing it: refreshing is the button's.
    func show(_ tab: GitHubIssueTab) async {
        userChoseTab = true
        await switchTo(tab)
    }

    private func switchTo(_ tab: GitHubIssueTab) async {
        guard self.tab != tab else { return }
        self.tab = tab
        refreshError = nil
        picked = nil
        if lists[tab] == nil, unavailable == nil || isRetryable { await fetchBoth(tab) }
    }

    /// Whether a failure is one a different request might not have.
    private var isRetryable: Bool {
        if case .failed = unavailable { return true }
        return false
    }

    // MARK: - Rows

    /// What is on the tab, before the search.
    var issues: [GitHubIssue] { lists[tab]?.issues ?? [] }

    /// The issues the search leaves. A reference to one issue shows that one,
    /// from either tab, or as fetched when it is on neither.
    var visibleIssues: [GitHubIssue] {
        if let reference = IssueReference(parsing: query), reference.matches(repository) {
            let loaded = lists.values.lazy.flatMap(\.issues).first { $0.number == reference.number }
            let found = loaded ?? (lookedUp?.number == reference.number ? lookedUp : nil)
            return found.map { [$0] } ?? []
        }
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return issues }
        return issues.filter { issue in
            words.allSatisfy { word in
                issue.title.localizedStandardContains(word)
                    || "#\(issue.number)".localizedStandardContains(word)
                    || (issue.author?.localizedStandardContains(word) ?? false)
                    || issue.labels.contains { $0.name.localizedStandardContains(word) }
            }
        }
    }

    /// The row Return starts: the one picked, else the first.
    var selected: GitHubIssue? {
        let rows = visibleIssues
        return rows.first { $0.number == picked } ?? rows.first
    }

    func select(_ number: Int) {
        picked = number
    }

    /// Moves the selection `offset` rows, stopping at either end.
    func moveSelection(by offset: Int) {
        let rows = visibleIssues
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.number == selected?.number } ?? 0
        picked = rows[min(max(current + offset, 0), rows.count - 1)].number
    }

    /// The session already working on `issue`, which makes it "in progress".
    func session(for issue: GitHubIssue) -> AgentSession? {
        openSession(issue.number)
    }

    /// When the tab on show was last read from GitHub, for the refresh
    /// button's tooltip.
    var updatedText: String {
        guard let fetchedAt = lists[tab]?.fetchedAt else { return "Refresh" }
        let age = RelativeAge.short(from: fetchedAt, now: now())
        return age == "now" ? "Updated just now" : "Updated \(age) ago"
    }

    // MARK: - Looking up

    private func queryChanged() {
        lookup?.cancel()
        lookup = nil
        guard let reference = IssueReference(parsing: query), reference.matches(repository) else {
            isLookingUp = false
            return
        }
        let known = lists.values.contains { $0.issues.contains { $0.number == reference.number } }
        guard !known, lookedUp?.number != reference.number else {
            isLookingUp = false
            return
        }
        isLookingUp = true
        lookup = Task { await lookUp(reference.number) }
    }

    private func lookUp(_ number: Int) async {
        defer { if !Task.isCancelled { isLookingUp = false } }
        guard let reply = try? await client.detail(at: path, number: number), !Task.isCancelled else { return }
        if reply.status == .ok, let issue = reply.detail?.issue { lookedUp = issue }
    }

    // MARK: - Starting

    /// Reads the selected issue in full, fresh, for an agent to start from. Or
    /// says there is a session for it already. `nil` when nothing starts, and
    /// ``failure`` says why unless there was nothing selected.
    func prepare() async -> Outcome? {
        guard let issue = selected, !isStarting else { return nil }
        if let session = openSession(issue.number) { return .resume(session) }

        isStarting = true
        failure = nil
        defer { isStarting = false }
        do {
            var reply = try await client.detail(at: path, number: issue.number)
            if reply.status == .unauthorized {
                await signInRefused()
                reply = try await client.detail(at: path, number: issue.number)
            }
            switch reply.status {
            case .ok:
                guard let detail = reply.detail else {
                    failure = "GitHub has no issue #\(issue.number)."
                    return nil
                }
                return .start(detail)
            case .unauthorized:
                failure = "GitHub refused the sign-in. Sign in again."
            case .notAccessible:
                failure = "The Herder GitHub App can\u{2019}t read this repository."
            case .permissionMissing:
                failure = "Herder doesn\u{2019}t have permission to read issues on this repository."
            case .error(let message):
                failure = message
            }
        } catch {
            failure = "herderd could not be reached."
        }
        return nil
    }

    /// Records why the worktree for an issue could not be made.
    func fail(_ message: String?) {
        failure = message ?? "Couldn\u{2019}t start from the issue."
    }
}

extension IssueReference {
    /// Whether it names an issue of `repository` (`owner/name`): a bare
    /// number does, and so does a link to that repository. Before herderd has
    /// said which repository it is, a link is given the benefit of the doubt.
    fileprivate func matches(_ repository: String?) -> Bool {
        guard let named = self.repository, let repository else { return true }
        return named.caseInsensitiveCompare(repository) == .orderedSame
    }
}
