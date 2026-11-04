import Clients
import ClientsTestSupport
import Foundation
import Testing

@testable import WorkspacesFeature

@Suite struct NewSessionModelTests {
    let git = StubGitClient()
    let repository = URL(filePath: "/code/api")
    let model: NewSessionModel

    init() {
        model = NewSessionModel(workspaceName: "api", repository: repository, git: git)
    }

    func seed(
        kind: GitRepositoryKind = .mainWorkingTree,
        branches: [String] = ["feature", "main"],
        checkout: String = "main"
    ) {
        git.seed(repository, kind)
        git.seed(branches: branches, at: repository)
        git.seed(worktrees: [
            GitWorktree(path: repository, checkout: .branch(checkout), isMainWorkingTree: true),
            GitWorktree(path: repository.appending(path: ".worktrees/feature"), checkout: .branch("feature"), isMainWorkingTree: false),
            GitWorktree(path: repository.appending(path: ".worktrees/old"), checkout: .detached(sha: "abc1234"), isMainWorkingTree: false),
        ], at: repository)
    }

    // MARK: - Loading

    @Test func loadingFillsTheListsAndPicksTheCheckedOutBranchAsBase() async {
        seed(checkout: "feature")

        await model.load()

        #expect(model.worktrees.count == 3)
        #expect(model.branches == ["feature", "main"])
        #expect(model.baseBranch == "feature")
        #expect(!model.isLoading)
        #expect(model.failure == nil)
    }

    @Test func theBaseFallsBackToMainThenMaster() async {
        git.seed(repository, .bare)
        git.seed(branches: ["dev", "master"], at: repository)

        await model.load()

        #expect(model.baseBranch == "master")
    }

    // MARK: - Choosing

    @Test func startsOnANewWorktree() {
        #expect(model.choice == .newWorktree)
    }

    @Test func selectingAWorktreeLeavesNewWorktree() async throws {
        seed()
        await model.load()

        model.select(model.worktrees[1])
        #expect(model.choice == .existing(model.worktrees[1].id))

        model.selectNewWorktree()
        #expect(model.choice == .newWorktree)
    }

    @Test func typingABranchNameChoosesNewWorktree() async {
        seed()
        await model.load()
        model.select(model.worktrees[0])

        model.editBranchName("x")

        #expect(model.choice == .newWorktree)
    }

    @Test func filteringMatchesBranchNamesAndShasWithoutCase() async {
        seed()
        await model.load()

        model.filter = "FEAT"
        #expect(model.filteredWorktrees.map(NewSessionModel.label) == ["feature"])

        model.filter = "abc"
        #expect(model.filteredWorktrees.map(NewSessionModel.label) == ["abc1234"])

        model.filter = "  "
        #expect(model.filteredWorktrees.count == 3)
    }

    // MARK: - The name

    @Test func anEmptyNameIsNotYetAProblemButCannotBeCreated() async {
        seed()
        await model.load()
        #expect(model.nameProblem == nil)
        #expect(!model.canCreate)
    }

    @Test func aMalformedNameIsExplained() async {
        seed()
        await model.load()

        model.editBranchName("has space")

        #expect(model.nameProblem == .invalid("can't contain spaces"))
        #expect(!model.canCreate)
    }

    @Test func anExistingBranchNameIsRefused() async {
        seed()
        await model.load()

        model.editBranchName("feature")

        #expect(model.nameProblem == .alreadyExists)
        #expect(!model.canCreate)
    }

    // MARK: - Creating

    @Test func createsTheWorktreeInsideTheWorkspace() async {
        seed()
        await model.load()
        model.editBranchName("agent/add-minimap")

        #expect(model.canCreate)
        #expect(await model.create())

        #expect(git.addedWorktrees == [
            .init(
                repository: repository,
                path: repository.appending(path: ".worktrees/agent-add-minimap"),
                newBranch: "agent/add-minimap",
                base: "main"
            )
        ])
    }

    @Test func createsFromTheChosenBase() async {
        seed()
        await model.load()
        model.editBranchName("fix")
        model.baseBranch = "feature"

        _ = await model.create()

        #expect(git.addedWorktrees.first?.base == "feature")
    }

    @Test func aBareRepositoryPutsItBesideTheOthers() async {
        seed(kind: .bare)
        await model.load()
        model.editBranchName("fix")

        _ = await model.create()

        #expect(git.addedWorktrees.first?.path == repository.appending(path: "fix"))
    }

    @Test func gitsRefusalIsShownAndNothingCloses() async {
        seed()
        git.failAddingWorktrees(with: "fatal: already exists")
        await model.load()
        model.editBranchName("fix")

        #expect(await !model.create())

        #expect(model.failure == "fatal: already exists")
        #expect(model.canCreate)
    }

    @Test func editingTheNameClearsAStaleFailure() async {
        seed()
        git.failAddingWorktrees(with: "boom")
        await model.load()
        model.editBranchName("fix")
        _ = await model.create()

        model.editBranchName("fix2")

        #expect(model.failure == nil)
    }

    @Test func anExistingWorktreeCannotBeSubmittedYet() async {
        seed()
        await model.load()
        model.editBranchName("fix")
        model.select(model.worktrees[0])

        #expect(!model.canCreate)
        #expect(await !model.create())
        #expect(git.addedWorktrees.isEmpty)
    }

    @Test func anUnreadableRepositoryLeavesEverythingDisabled() async {
        git.seedUnreadable(repository)

        await model.load()

        #expect(model.failure != nil)
        model.editBranchName("fix")
        #expect(!model.canCreate)
    }
}
