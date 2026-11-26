import Core
import Foundation
import TestSupport
import Testing

@testable import RepositoriesFeature

@Suite(.timeLimit(.minutes(1))) @MainActor struct IssueListModelTests {
    let client = StubGitHubIssuesClient()
    let fetched = Date(timeIntervalSince1970: 1_000_000)
    let model: IssueListModel
    let signInRefusals = Counter()

    final class Counter {
        var count = 0
    }

    init(openSessions: @escaping (Int) -> AgentSession? = { _ in nil }) {
        let refusals = signInRefusals
        model = IssueListModel(
            workspaceName: "api", path: "/code/api", client: client, openSession: openSessions,
            signInRefused: { refusals.count += 1 },
            now: { Date(timeIntervalSince1970: 1_000_000 + 180) }
        )
    }

    func issue(
        _ number: Int, _ title: String = "An issue", author: String? = "ada", labels: [String] = []
    ) -> GitHubIssue {
        GitHubIssue(
            number: number, url: URL(string: "https://github.com/o/r/issues/\(number)")!, title: title,
            labels: labels.map { GitHubIssue.Label(name: $0, color: "d73a4a") }, author: author
        )
    }

    func list(
        _ issues: [GitHubIssue], assigned: Int? = nil, open: Int? = nil, fetched: Date? = nil,
        status: GitHubIssueStatus = .ok
    ) -> GitHubIssueList {
        GitHubIssueList(
            repository: "o/r", status: status, issues: issues, fetchedAt: fetched ?? self.fetched,
            assignedCount: assigned ?? issues.count, openCount: open ?? issues.count
        )
    }

    func nothingCached() -> GitHubIssueList {
        GitHubIssueList(repository: "o/r", status: .ok)
    }

    func session(forIssue number: Int, name: String = "Fix it") -> AgentSession {
        AgentSession(
            id: UUID(), agentID: "claude-code", agentName: "Claude Code", worktree: WorkspaceID(URL(filePath: "/code/api")),
            title: name, name: name, startedAt: fetched,
            issue: LinkedIssue(number: number, title: "t", url: URL(string: "https://github.com/o/r/issues/\(number)")!)
        )
    }

    // MARK: - Opening

    @Test func openingAsksForTheFirstTabFromMemoryAndFromGitHubTogether() async {
        client.answer(nothingCached(), tab: .assigned, freshness: .cached)
        client.answer(list([issue(1)], open: 5), tab: .assigned, freshness: .fresh)

        await model.load()

        #expect(Set(client.calls.map(\.freshness)) == [.cached, .fresh])
        #expect(client.calls.allSatisfy { $0.tab == .assigned && $0.path == "/code/api" })
        #expect(model.issues.map(\.number) == [1])
        #expect(model.tab == .assigned)
        #expect(model.repository == "o/r")
    }

    @Test func theFreshAnswerReplacesTheCachedOne() async {
        client.answer(list([issue(1, "Old")]), tab: .assigned, freshness: .cached)
        client.answer(list([issue(1, "New"), issue(2)]), tab: .assigned, freshness: .fresh)

        await model.load()

        #expect(model.issues.map(\.title) == ["New", "An issue"])
    }

    @Test func aCachedAnswerShowsWhileTheFreshOneIsStillOnItsWay() async throws {
        client.answer(list([issue(1)]), tab: .assigned, freshness: .cached)
        client.answer(list([issue(1), issue(2)]), tab: .assigned, freshness: .fresh)
        client.delay(.milliseconds(50))

        let loading = Task { await model.load() }
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.isRefreshing)
        #expect(model.isLoading)

        await loading.value
        #expect(!model.isRefreshing)
        #expect(!model.isLoading)
    }

    @Test func nothingAssignedOpensOnAllOpen() async {
        client.answer(list([], assigned: 0, open: 2), tab: .assigned, freshness: .fresh)
        client.answer(nothingCached(), tab: .assigned, freshness: .cached)
        client.answer(list([issue(1), issue(2)], assigned: 0, open: 2), tab: .open, freshness: .fresh)
        client.answer(nothingCached(), tab: .open, freshness: .cached)

        await model.load()

        #expect(model.tab == .open)
        #expect(model.issues.map(\.number) == [1, 2])
        #expect(model.count(for: .assigned) == 0)
        #expect(model.count(for: .open) == 2)
    }

    @Test func somethingAssignedStaysOnAssignedToMe() async {
        client.answer(list([issue(1)], assigned: 1, open: 8), tab: .assigned, freshness: .fresh)
        client.answer(nothingCached(), tab: .assigned, freshness: .cached)

        await model.load()

        #expect(model.tab == .assigned)
        #expect(model.count(for: .assigned) == 1)
        #expect(model.count(for: .open) == 8)
        #expect(client.calls.allSatisfy { $0.tab == .assigned })
    }

    // MARK: - Tabs

    func seedBothTabs() {
        client.answer(nothingCached(), tab: .assigned, freshness: .cached)
        client.answer(list([issue(1)], assigned: 1, open: 3), tab: .assigned, freshness: .fresh)
        client.answer(nothingCached(), tab: .open, freshness: .cached)
        client.answer(list([issue(1), issue(2), issue(3)], assigned: 1, open: 3), tab: .open, freshness: .fresh)
    }

    @Test func switchingTabsAsksForTheOtherTabOnceAndNeverAgain() async {
        seedBothTabs()
        await model.load()

        await model.show(.open)
        await model.show(.assigned)
        await model.show(.open)

        #expect(client.calls.filter { $0.tab == .open }.count == 2)
        #expect(model.issues.map(\.number) == [1, 2, 3])
    }

    @Test func aTabTheUserChoseIsNotSwitchedAwayFromWhenNothingIsAssigned() async {
        client.answer(nothingCached(), tab: .assigned, freshness: .cached)
        client.answer(list([], assigned: 0, open: 3), tab: .assigned, freshness: .fresh)
        await model.show(.assigned)

        await model.load()

        #expect(model.tab == .assigned)
    }

    // MARK: - Refreshing

    @Test func refreshingAsksGitHubForTheTabOnShowAndNothingElse() async {
        seedBothTabs()
        await model.load()
        let before = client.calls.count

        await model.refresh()

        #expect(client.calls.dropFirst(before) == [.init(path: "/code/api", tab: .assigned, freshness: .fresh)])
    }

    @Test func theRefreshButtonSpinsWhileARequestIsInFlight() async throws {
        seedBothTabs()
        await model.load()
        client.delay(.milliseconds(50))

        let refreshing = Task { await model.refresh() }
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.isRefreshing)

        await refreshing.value
        #expect(!model.isRefreshing)
    }

    @Test func theTooltipSaysHowLongAgoGitHubWasAsked() async {
        seedBothTabs()
        await model.load()

        #expect(model.updatedText == "Updated 3m ago")
    }

    @Test func aFailedRefreshKeepsTheRowsAndSaysWhyInOneLine() async {
        seedBothTabs()
        await model.load()
        client.answer(list([], status: .error("GitHub answered 502")), tab: .assigned, freshness: .fresh)

        await model.refresh()

        #expect(model.issues.map(\.number) == [1])
        #expect(model.refreshError == "GitHub answered 502")
        #expect(model.unavailable == nil)
    }

    @Test func herderdBeingUnreachableDuringARefreshIsTheSameLine() async {
        seedBothTabs()
        await model.load()
        client.fail(tab: .assigned, freshness: .fresh)

        await model.refresh()

        #expect(model.issues.count == 1)
        #expect(model.refreshError == "herderd could not be reached.")
    }

    @Test func aRefreshThatWorksClearsTheLine() async {
        seedBothTabs()
        await model.load()
        client.fail(tab: .assigned, freshness: .fresh)
        await model.refresh()
        client.answer(list([issue(1), issue(4)]), tab: .assigned, freshness: .fresh)

        await model.refresh()

        #expect(model.refreshError == nil)
        #expect(model.issues.map(\.number) == [1, 4])
    }

    @Test func withNothingToKeepAFailureReplacesTheList() async {
        client.answer(nothingCached(), tab: .assigned, freshness: .cached)
        client.answer(list([], status: .error("GitHub answered 502")), tab: .assigned, freshness: .fresh)

        await model.load()

        #expect(model.unavailable == .failed("GitHub answered 502"))
    }

    @Test func nothingIsAskedForByItselfOnceOpen() async {
        seedBothTabs()
        await model.load()
        let before = client.calls.count

        await model.show(.open)
        await model.show(.assigned)
        model.query = "x"

        #expect(client.calls.count == before + 2)
    }

    // MARK: - Unavailable

    @Test func notBeingSignedInSaysSoAfterTryingToRefreshTheTokenOnce() async {
        client.answer(GitHubIssueList(repository: "o/r", status: .unauthorized), tab: .assigned, freshness: .cached)
        client.answer(GitHubIssueList(repository: "o/r", status: .unauthorized), tab: .assigned, freshness: .fresh)

        await model.load()

        #expect(model.unavailable == .notSignedIn)
        #expect(signInRefusals.count == 1)
        #expect(client.calls.filter { $0.freshness == .fresh }.count == 2)
    }

    @Test func aRefusedTokenThatRefreshingMendsShowsTheList() async {
        client.answer(nothingCached(), tab: .assigned, freshness: .cached)
        client.answer(GitHubIssueList(repository: "o/r", status: .unauthorized), tab: .assigned, freshness: .fresh)
        let mended = list([issue(1)])
        let client = client
        let model = IssueListModel(
            workspaceName: "api", path: "/code/api", client: client, openSession: { _ in nil },
            signInRefused: { client.answer(mended, tab: .assigned, freshness: .fresh) }
        )

        await model.load()

        #expect(model.unavailable == nil)
        #expect(model.issues.map(\.number) == [1])
    }

    @Test func anAppThatIsNotInstalledSaysWhichRepository() async {
        client.answer(GitHubIssueList(repository: "o/r", status: .notAccessible), tab: .assigned, freshness: .fresh)
        client.answer(nothingCached(), tab: .assigned, freshness: .cached)

        await model.load()

        #expect(model.unavailable == .notInstalled("o/r"))
    }

    @Test func anInstallationThatHasNotApprovedIssuesSaysWhichRepository() async {
        client.answer(GitHubIssueList(repository: "o/r", status: .permissionMissing), tab: .assigned, freshness: .fresh)
        client.answer(nothingCached(), tab: .assigned, freshness: .cached)

        await model.load()

        #expect(model.unavailable == .permissionMissing("o/r"))
    }

    @Test func loadingAgainAfterFixingItClearsWhatWasWrong() async {
        client.answer(GitHubIssueList(repository: "o/r", status: .permissionMissing), tab: .assigned, freshness: .fresh)
        client.answer(nothingCached(), tab: .assigned, freshness: .cached)
        await model.load()
        client.answer(list([issue(1)]), tab: .assigned, freshness: .fresh)

        await model.load()

        #expect(model.unavailable == nil)
        #expect(model.issues.count == 1)
    }

    // MARK: - Search

    func seedFour() async {
        client.answer(nothingCached(), tab: .assigned, freshness: .cached)
        client.answer(list([
            issue(10, "Crash on save", author: "ada", labels: ["bug"]),
            issue(11, "Add a minimap", author: "bob", labels: ["enhancement"]),
            issue(12, "Café menu", author: "ada"),
            issue(123, "Slow launch", author: "cy"),
        ]), tab: .assigned, freshness: .fresh)
        await model.load()
    }

    @Test func searchFiltersByTitleLabelAuthorAndNumber() async {
        await seedFour()

        model.query = "minimap"
        #expect(model.visibleIssues.map(\.number) == [11])
        model.query = "bug"
        #expect(model.visibleIssues.map(\.number) == [10])
        model.query = "ADA"
        #expect(model.visibleIssues.map(\.number) == [10, 12])
        model.query = "cafe"
        #expect(model.visibleIssues.map(\.number) == [12])
        model.query = "ada save"
        #expect(model.visibleIssues.map(\.number) == [10])
        model.query = ""
        #expect(model.visibleIssues.count == 4)
    }

    @Test func pastingAHashJumpsToThatIssueWithoutAskingGitHub() async {
        await seedFour()

        model.query = "#123"

        #expect(model.visibleIssues.map(\.number) == [123])
        #expect(model.selected?.number == 123)
        #expect(client.detailCalls.isEmpty)
    }

    @Test func pastingALinkJumpsToThatIssueToo() async {
        await seedFour()

        model.query = "https://github.com/o/r/issues/11"

        #expect(model.selected?.number == 11)
        #expect(client.detailCalls.isEmpty)
    }

    @Test func anIssueThatIsNotLoadedIsFetchedAndShown() async {
        await seedFour()
        client.answer(
            GitHubIssueDetailReply(status: .ok, detail: GitHubIssueDetail(issue: issue(500, "Far down"), body: "")),
            number: 500
        )

        model.query = "#500"
        for _ in 0..<50 where model.isLookingUp { try? await Task.sleep(for: .milliseconds(10)) }

        #expect(client.detailCalls == [500])
        #expect(model.visibleIssues.map(\.number) == [500])
        #expect(!model.isLookingUp)
    }

    @Test func anIssueThatDoesNotExistLeavesNothingToShow() async {
        await seedFour()
        client.answer(GitHubIssueDetailReply(status: .ok, detail: nil), number: 404)

        model.query = "#404"
        for _ in 0..<50 where model.isLookingUp { try? await Task.sleep(for: .milliseconds(10)) }

        #expect(model.visibleIssues.isEmpty)
    }

    @Test func aLinkToAnotherRepositoryIsNotJumpedTo() async {
        await seedFour()

        model.query = "https://github.com/someone/else/issues/11"

        #expect(client.detailCalls.isEmpty)
        #expect(model.visibleIssues.isEmpty)
    }

    // MARK: - Selection

    @Test func theFirstRowIsSelectedAndTheArrowsMoveItAndStopAtTheEnds() async {
        await seedFour()
        #expect(model.selected?.number == 10)

        model.moveSelection(by: -1)
        #expect(model.selected?.number == 10)
        model.moveSelection(by: 1)
        model.moveSelection(by: 1)
        #expect(model.selected?.number == 12)
        model.moveSelection(by: 10)
        #expect(model.selected?.number == 123)
        model.moveSelection(by: 1)
        #expect(model.selected?.number == 123)
    }

    @Test func aSelectionTheSearchHidesFallsBackToTheFirstRowLeft() async {
        await seedFour()
        model.select(123)

        model.query = "ada"

        #expect(model.selected?.number == 10)
    }

    // MARK: - Starting

    @Test func startingReadsTheIssueFreshAndHandsItBack() async {
        await seedFour()
        let detail = GitHubIssueDetail(issue: issue(10, "Crash on save"), body: "It crashes.")
        client.answer(GitHubIssueDetailReply(status: .ok, detail: detail), number: 10)

        let outcome = await model.prepare()

        #expect(outcome == .start(detail))
        #expect(client.detailCalls == [10])
        #expect(model.failure == nil)
        #expect(!model.isStarting)
    }

    @Test func anIssueWithASessionOpensItInsteadAndAsksNothing() async {
        let open = session(forIssue: 10)
        let model = IssueListModel(
            workspaceName: "api", path: "/code/api", client: client,
            openSession: { $0 == 10 ? open : nil }
        )
        client.answer(nothingCached(), tab: .assigned, freshness: .cached)
        client.answer(list([issue(10), issue(11)]), tab: .assigned, freshness: .fresh)
        await model.load()

        #expect(model.session(for: issue(10))?.id == open.id)
        #expect(model.session(for: issue(11)) == nil)
        #expect(await model.prepare() == .resume(open))
        #expect(client.detailCalls.isEmpty)
    }

    @Test func aFailedDetailFetchShowsTheErrorAndStartsNothing() async {
        await seedFour()
        client.failDetail(number: 10)

        #expect(await model.prepare() == nil)

        #expect(model.failure == "herderd could not be reached.")
        #expect(!model.isStarting)
    }

    @Test func githubSayingNoShowsItsWords() async {
        await seedFour()
        client.answer(GitHubIssueDetailReply(status: .error("GitHub answered 502")), number: 10)

        #expect(await model.prepare() == nil)

        #expect(model.failure == "GitHub answered 502")
    }

    @Test func anIssueThatIsGoneStartsNothing() async {
        await seedFour()
        client.answer(GitHubIssueDetailReply(status: .ok, detail: nil), number: 10)

        #expect(await model.prepare() == nil)

        #expect(model.failure == "GitHub has no issue #10.")
    }

    @Test func nothingSelectedStartsNothingAndAsksNothing() async {
        client.answer(nothingCached(), tab: .assigned, freshness: .cached)
        client.answer(list([], assigned: 1, open: 1), tab: .assigned, freshness: .fresh)
        await model.load()

        #expect(await model.prepare() == nil)
        #expect(client.detailCalls.isEmpty)
        #expect(model.failure == nil)
    }
}
