import Core
import Foundation
import TestSupport
import Testing

@testable import RepositoriesFeature

@Suite @MainActor struct NewOrderModelTests {
    let repository = URL(filePath: "/code/api")
    let git = StubGitClient()
    let namer = StubSessionNamer(.name(SessionName(type: .feat, slug: "add-minimap", title: "Add a minimap")))
    let model: NewOrderModel

    init() {
        git.seed(repository, .mainWorkingTree)
        git.seed(branches: ["main"], at: repository)
        git.seed(fetchedBase: "origin/main", at: repository)
        model = NewOrderModel(
            git: git,
            namer: namer,
            naming: { NamingConfiguration(endpoint: URL(string: "http://127.0.0.1:3456")!, apiKey: "k") },
            namingTimeout: .milliseconds(100)
        )
    }

    // MARK: - Success

    @Test func planItCutsANamedWorktreeFromTheFetchedDefaultBranch() async throws {
        model.text = "  add a minimap to the editor \n"

        let order = try #require(await model.submit(in: repository))

        #expect(git.addedWorktrees == [
            .init(
                repository: repository,
                path: repository.appending(path: "feat/add-minimap"),
                newBranch: "feat/add-minimap",
                base: "origin/main"
            )
        ])
        #expect(order.worktree == repository.appending(path: "feat/add-minimap"))
        #expect(order.title == "Add a minimap")
        #expect(order.prompt == "add a minimap to the editor")
        #expect(model.text.isEmpty)
        #expect(model.failure == nil)
        #expect(!model.isWorking)
    }

    @Test func theAgentIsToldTheTextInTheUsersTemplateButNamingSeesItAsTyped() async throws {
        let templated = NewOrderModel(
            git: git, namer: namer, naming: { NamingConfiguration(endpoint: URL(string: "http://x")!) },
            promptTemplate: { "/grill-me {prompt}" }, namingTimeout: .milliseconds(100)
        )
        templated.text = "add a minimap"

        let order = try #require(await templated.submit(in: repository))

        #expect(order.prompt == "/grill-me add a minimap")
        #expect(namer.prompts == ["add a minimap"])
    }

    @Test func theNamingCallAndTheFetchBothHappen() async throws {
        model.text = "add a minimap"

        _ = await model.submit(in: repository)

        #expect(namer.prompts == ["add a minimap"])
        #expect(namer.configurations.first?.apiKey == "k")
        #expect(git.fetchedRepositories == [repository])
    }

    @Test func aBranchThatExistsGetsANumberOnTheEnd() async throws {
        git.seed(branches: ["main", "feat/add-minimap", "feat/add-minimap-2"], at: repository)
        model.text = "add a minimap"

        let order = try #require(await model.submit(in: repository))

        #expect(git.addedWorktrees.map(\.newBranch) == ["feat/add-minimap-3"])
        #expect(order.worktree == repository.appending(path: "feat/add-minimap-3"))
    }

    @Test func theTypeCanBeFixOrChore() async throws {
        namer.answer(.name(SessionName(type: .fix, slug: "Crash On Save!", title: "Fix crash")))
        model.text = "it crashes on save"

        _ = await model.submit(in: repository)

        #expect(git.addedWorktrees.map(\.newBranch) == ["fix/crash-on-save"])
    }

    // MARK: - Fallbacks

    @Test func aFailedNamingCallFallsBackToAChoreBranchWithNoError() async throws {
        namer.answer(.failure)
        model.text = "add a minimap to the editor"

        let order = try #require(await model.submit(in: repository))

        let branch = try #require(git.addedWorktrees.first?.newBranch)
        #expect(branch.hasPrefix("chore/"))
        #expect(branch.dropFirst("chore/".count).split(separator: "-").count == 2)
        #expect(order.title == "add a minimap to the editor")
        #expect(model.failure == nil)
    }

    @Test func aNamingCallThatTakesTooLongFallsBackToo() async throws {
        namer.answer(.hangs)
        model.text = "add a minimap"

        let order = try #require(await model.submit(in: repository))

        #expect(git.addedWorktrees.first?.newBranch.hasPrefix("chore/") == true)
        #expect(order.title == "add a minimap")
        #expect(model.failure == nil)
    }

    @Test func aTitleFromThePromptIsItsFirstLineAndNoLongerThanATabShows() async throws {
        namer.answer(.failure)
        model.text = "first line\nsecond line"
        #expect(await model.submit(in: repository)?.title == "first line")

        namer.answer(.failure)
        model.text = String(repeating: "word ", count: 30)
        let long = try #require(await model.submit(in: repository)?.title)
        #expect(long.count <= 40)
    }

    @Test func aFailedFetchStillCutsFromTheExistingRemoteTrackingRef() async throws {
        git.failFetching(with: "offline")
        git.seed(refs: [
            GitRef(name: "main", kind: .branch, date: .now),
            GitRef(name: "origin/main", kind: .remoteBranch, date: .now),
        ], in: repository)
        model.text = "add a minimap"

        let order = try #require(await model.submit(in: repository))

        #expect(git.addedWorktrees.map(\.base) == ["origin/main"])
        #expect(order.worktree == repository.appending(path: "feat/add-minimap"))
        #expect(model.failure == nil)
    }

    @Test func aFailedFetchWithNoRemoteRefCutsFromTheLocalDefaultBranch() async throws {
        git.failFetching(with: "offline")
        model.text = "add a minimap"

        let order = try #require(await model.submit(in: repository))

        #expect(git.addedWorktrees.map(\.base) == ["main"])
        #expect(order.worktree == repository.appending(path: "feat/add-minimap"))
        #expect(model.failure == nil)
    }

    // MARK: - Failures

    @Test func noDefaultBranchKeepsTheTextAndSaysSo() async throws {
        git.seed(fetchedBase: nil, at: repository)
        git.seed(branches: ["trunk-only"], at: repository)
        model.text = "add a minimap"

        #expect(await model.submit(in: repository) == nil)

        #expect(model.text == "add a minimap")
        #expect(model.failure != nil)
        #expect(git.addedWorktrees.isEmpty)
    }

    @Test func aWorktreeThatCannotBeMadeKeepsTheTextAndShowsGitsWords() async throws {
        git.failAddingWorktrees(with: "fatal: boom")
        model.text = "add a minimap"

        #expect(await model.submit(in: repository) == nil)

        #expect(model.text == "add a minimap")
        #expect(model.failure == "fatal: boom")
        #expect(!model.isWorking)
    }

    @Test func aRepositoryThatCannotHoldAWorktreeKeepsTheText() async throws {
        let linked = URL(filePath: "/code/linked")
        git.seed(linked, .linkedWorktree(mainRepository: repository))
        model.text = "add a minimap"

        #expect(await model.submit(in: linked) == nil)

        #expect(model.text == "add a minimap")
        #expect(model.failure != nil)
    }

    // MARK: - Input

    @Test func blankTextCannotBeSubmitted() async throws {
        model.text = " \n\t "
        #expect(!model.canSubmit)

        #expect(await model.submit(in: repository) == nil)

        #expect(namer.prompts.isEmpty)
        #expect(git.fetchedRepositories.isEmpty)
        #expect(model.failure == nil)

        model.text = "x"
        #expect(model.canSubmit)
    }

    // MARK: - From an issue

    func detail(
        number: Int = 144, title: String = "Start an agent from a GitHub issue (\"From issue\")"
    ) -> GitHubIssueDetail {
        GitHubIssueDetail(
            issue: GitHubIssue(
                number: number, url: URL(string: "https://github.com/o/r/issues/\(number)")!, title: title
            ),
            body: "Add the button.",
            comments: [.init(author: "ada", body: "Plan mode please.")]
        )
    }

    @Test func anIssueGetsABranchNamedForItsNumberAndTitleCutFromTheFetchedDefaultBranch() async throws {
        let started = try #require(await model.start(from: detail(), in: repository))

        let branch = "issue/144-start-an-agent-from-a-github-issue-from"
        #expect(git.addedWorktrees == [
            .init(repository: repository, path: repository.appending(path: branch), newBranch: branch, base: "origin/main")
        ])
        #expect(started.worktree == repository.appending(path: branch))
        #expect(model.failure == nil)
        #expect(!model.isWorking)
    }

    @Test func theBranchNeverAsksTheNamer() async throws {
        _ = await model.start(from: detail(), in: repository)

        #expect(namer.prompts.isEmpty)
        #expect(git.fetchedRepositories == [repository])
    }

    @Test func aBranchThatExistsGetsANumberOnTheEndLikeAnOrderBranch() async throws {
        git.seed(branches: ["main", "issue/7-crash", "issue/7-crash-2"], at: repository)

        _ = await model.start(from: detail(number: 7, title: "Crash"), in: repository)

        #expect(git.addedWorktrees.map(\.newBranch) == ["issue/7-crash-3"])
    }

    @Test func theSessionIsNamedByTheIssueTitleCutToATabsWidth() async throws {
        let started = try #require(await model.start(from: detail(), in: repository))

        #expect(started.title == String(detail().issue.title.prefix(NewOrderModel.maxTitleLength)))
        #expect(started.title.count == 40)
    }

    @Test func theIssueIsRememberedWithTheSession() async throws {
        let started = try #require(await model.start(from: detail(number: 9, title: "Nine"), in: repository))

        #expect(started.issue == LinkedIssue(number: 9, title: "Nine", url: URL(string: "https://github.com/o/r/issues/9")!))
    }

    @Test func thePromptIsTheIssueThroughTheUsersTemplate() async throws {
        let templated = NewOrderModel(
            git: git, namer: namer, naming: { NamingConfiguration(endpoint: URL(string: "http://x")!) },
            promptTemplate: { "/grill-me {prompt}" }
        )

        let started = try #require(await templated.start(from: detail(number: 9, title: "Nine"), in: repository))

        #expect(started.prompt == """
            /grill-me #9 Nine

            https://github.com/o/r/issues/9

            Add the button.

            Comments, oldest first:

            @ada:
            Plan mode please.
            """)
    }

    @Test func anIssueWithoutATemplateIsTheIssueAsItIs() async throws {
        let started = try #require(await model.start(from: detail(number: 9, title: "Nine"), in: repository))

        #expect(started.prompt.hasPrefix("#9 Nine\n\nhttps://github.com/o/r/issues/9\n\nAdd the button."))
    }

    @Test func aFailedFetchStillCutsFromTheLocalDefaultBranch() async throws {
        git.failFetching(with: "offline")

        _ = try #require(await model.start(from: detail(), in: repository))

        #expect(git.addedWorktrees.map(\.base) == ["main"])
    }

    @Test func aWorktreeThatCannotBeMadeStartsNothingAndShowsGitsWords() async throws {
        git.failAddingWorktrees(with: "fatal: boom")

        #expect(await model.start(from: detail(), in: repository) == nil)

        #expect(model.failure == "fatal: boom")
        #expect(!model.isWorking)
    }

    @Test func noDefaultBranchStartsNothing() async throws {
        git.seed(fetchedBase: nil, at: repository)
        git.seed(branches: ["trunk-only"], at: repository)

        #expect(await model.start(from: detail(), in: repository) == nil)

        #expect(model.failure != nil)
        #expect(git.addedWorktrees.isEmpty)
    }

    @Test func whatWasTypedInTheCardIsLeftAlone() async throws {
        model.text = "something else"

        _ = await model.start(from: detail(), in: repository)

        #expect(model.text == "something else")
    }
}
