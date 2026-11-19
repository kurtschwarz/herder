import Core
import Darwin
import Foundation
@testable import Services
import Testing

/// The layout scenarios of `LiveGitClientTests` (`repositoryKind`, `worktrees`,
/// `branches`, `gitDirectory`, `checkout`, `status`),
/// against a live `herderd`. `packages/herderd/tests/repository_kind.rs` runs
/// the same scenarios against the daemon alone. Skipped, like the daemon client
/// tests, when `just test` has not built the binary.
@Suite(.timeLimit(.minutes(1))) struct DaemonGitClientTests {
    let fixture: GitFixture
    let socket = URL(filePath: "/tmp/herderd-git-\(UUID().uuidString.prefix(8)).sock")
    let daemon: LiveDaemonClient
    let client: DaemonGitClient

    init() throws {
        fixture = try GitFixture("DaemonGitClientTests")
        daemon = LiveDaemonClient(socket: socket, executable: LiveDaemonClientTests.binary, client: "test")
        client = DaemonGitClient(daemon: daemon)
    }

    /// Ends the daemon the test started.
    func stop() {
        daemon.launchedPIDs.forEach { kill($0, SIGKILL) }
        try? FileManager.default.removeItem(at: socket)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func plainFolderIsNotARepository() async throws {
        defer { stop() }
        let url = try fixture.makeDirectory("plain")
        #expect(try await client.repositoryKind(at: url) == .notARepository)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func repositoryRootIsAMainWorkingTree() async throws {
        defer { stop() }
        let url = try fixture.makeRepository("repo")
        #expect(try await client.repositoryKind(at: url) == .mainWorkingTree)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func subdirectoryOfARepositoryIsNotARepository() async throws {
        defer { stop() }
        let nested = try fixture.makeRepository("repo").appending(path: "src")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        #expect(try await client.repositoryKind(at: nested) == .notARepository)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func bareRepositoryIsRecognised() async throws {
        defer { stop() }
        let url = try fixture.makeDirectory("api.git")
        try fixture.git("init", "--bare", in: url)
        #expect(try await client.repositoryKind(at: url) == .bare)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func linkedWorktreeReportsItsMainRepository() async throws {
        defer { stop() }
        let repository = try fixture.makeRepository("repo")
        let worktree = fixture.directory.appending(path: "feature")
        try fixture.git("worktree", "add", worktree.path(percentEncoded: false), "-b", "feature", in: repository)

        let kind = try await client.repositoryKind(at: worktree)
        #expect(kind == .linkedWorktree(mainRepository: repository.resolvingSymlinksInPath()))
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func worktreeOfABareRepositoryReportsTheBareDirectory() async throws {
        defer { stop() }
        let bare = try fixture.makeDirectory("origin.git")
        try fixture.git("init", "--bare", "--initial-branch=main", in: bare)
        try fixture.seed(bare, as: "origin")
        let worktree = fixture.directory.appending(path: "bare-feature")
        try fixture.git("worktree", "add", worktree.path(percentEncoded: false), "main", in: bare)

        let kind = try await client.repositoryKind(at: worktree)
        #expect(kind == .linkedWorktree(mainRepository: bare.resolvingSymlinksInPath()))
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func aProjectWhoseDotGitIsBareIsABareRepositoryAndItsWorktreeNamesTheProject() async throws {
        defer { stop() }
        let project = try fixture.makeDirectory("project")
        let dotGit = project.appending(path: ".git")
        try FileManager.default.createDirectory(at: dotGit, withIntermediateDirectories: true)
        try fixture.git("init", "--bare", "--initial-branch=main", in: dotGit)
        try fixture.seed(dotGit, as: "project")
        try fixture.git("worktree", "add", "main", "main", in: project)

        #expect(try await client.repositoryKind(at: project) == .bare)
        let kind = try await client.repositoryKind(at: project.appending(path: "main"))
        #expect(kind == .linkedWorktree(mainRepository: project.resolvingSymlinksInPath()))
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func aDotGitFileNamingABareRepositoryIsBareAndItsWorktreePointsBackAtTheProject() async throws {
        defer { stop() }
        let project = try fixture.makeDirectory("project")
        let bare = project.appending(path: ".bare")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        try fixture.git("init", "--bare", "--initial-branch=main", in: bare)
        try Data("gitdir: ./.bare\n".utf8).write(to: project.appending(path: ".git"))
        try fixture.seed(bare, as: "project")
        try fixture.git("worktree", "add", "main", "main", in: project)

        #expect(try await client.repositoryKind(at: project) == .bare)
        // Not `.bare`, which is where the files are, and not the worktree itself.
        let kind = try await client.repositoryKind(at: project.appending(path: "main"))
        #expect(kind == .linkedWorktree(mainRepository: project.resolvingSymlinksInPath()))
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func missingFolderIsNotARepository() async throws {
        defer { stop() }
        let url = fixture.directory.appending(path: "nothing-here")
        #expect(try await client.repositoryKind(at: url) == .notARepository)
    }

    // MARK: - worktrees

    func addWorktree(_ name: String, to repository: URL) throws -> URL {
        let path = fixture.directory.appending(path: name)
        try fixture.git("worktree", "add", path.path(percentEncoded: false), "-b", name, in: repository)
        return path
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func repositoryWithoutWorktreesListsOnlyItsMainWorkingTree() async throws {
        defer { stop() }
        let repository = try fixture.makeRepository("repo")
        let trees = try await client.worktrees(at: repository)
        #expect(trees.count == 1)
        #expect(trees.first?.path == repository.resolvingSymlinksInPath())
        #expect(trees.first?.checkout == .branch("main"))
        #expect(trees.first?.isMainWorkingTree == true)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func worktreesReportWhenTheyLastChanged() async throws {
        defer { stop() }
        let repository = try fixture.makeRepository("repo")
        _ = try addWorktree("feature", to: repository)

        for tree in try await client.worktrees(at: repository) {
            let activity = try #require(tree.lastActivity)
            #expect(abs(activity.timeIntervalSinceNow) < 120)
        }
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func linkedWorktreesFollowMainAndSortByBranch() async throws {
        defer { stop() }
        let repository = try fixture.makeRepository("repo")
        for branch in ["zeta", "alpha"] { _ = try addWorktree(branch, to: repository) }

        let trees = try await client.worktrees(at: repository)
        #expect(trees.map(\.checkout) == [.branch("main"), .branch("alpha"), .branch("zeta")])
        #expect(trees.map(\.isMainWorkingTree) == [true, false, false])
        #expect(trees[1].path == fixture.directory.appending(path: "alpha").resolvingSymlinksInPath())
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func detachedWorktreeShowsShortShaAndSortsLast() async throws {
        defer { stop() }
        let repository = try fixture.makeRepository("repo")
        let detached = fixture.directory.appending(path: "detached")
        try fixture.git("worktree", "add", "--detach", detached.path(percentEncoded: false), in: repository)
        _ = try addWorktree("beta", to: repository)

        let sha = try fixture.git("rev-parse", "--short=7", "HEAD", in: repository)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trees = try await client.worktrees(at: repository)
        #expect(trees.map(\.checkout) == [.branch("main"), .branch("beta"), .detached(sha: sha)])
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func bareRepositoryContributesOnlyItsWorktrees() async throws {
        defer { stop() }
        let bare = try fixture.makeDirectory("origin.git")
        try fixture.git("init", "--bare", "--initial-branch=main", in: bare)
        try fixture.seed(bare, as: "origin")
        let worktree = fixture.directory.appending(path: "bare-main")
        try fixture.git("worktree", "add", worktree.path(percentEncoded: false), "main", in: bare)

        let trees = try await client.worktrees(at: bare)
        #expect(trees.count == 1)
        #expect(trees.first?.checkout == .branch("main"))
        #expect(trees.first?.isMainWorkingTree == false)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func worktreeWhoseFolderWasDeletedIsSkipped() async throws {
        defer { stop() }
        let repository = try fixture.makeRepository("repo")
        try FileManager.default.removeItem(at: try addWorktree("gone", to: repository))

        #expect(try await client.worktrees(at: repository).map(\.checkout) == [.branch("main")])
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func nonRepositoriesAndLinkedWorktreesHaveNoWorktrees() async throws {
        defer { stop() }
        #expect(try await client.worktrees(at: try fixture.makeDirectory("plain")).isEmpty)

        let repository = try fixture.makeRepository("repo")
        let linked = try addWorktree("linked", to: repository)
        #expect(try await client.worktrees(at: linked).isEmpty)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func theFoldersBesideABareDotGitAreItsWorktrees() async throws {
        defer { stop() }
        let project = try fixture.makeDirectory("project")
        let dotGit = project.appending(path: ".git")
        try FileManager.default.createDirectory(at: dotGit, withIntermediateDirectories: true)
        try fixture.git("init", "--bare", "--initial-branch=main", in: dotGit)
        try fixture.seed(dotGit, as: "project")
        try fixture.git("worktree", "add", "main", "main", in: project)

        let trees = try await client.worktrees(at: project)
        #expect(trees.map(\.checkout) == [.branch("main")])
        #expect(trees.first?.path == project.appending(path: "main").resolvingSymlinksInPath())
        #expect(trees.first?.isMainWorkingTree == false)
        #expect(try await client.branches(at: project) == ["main"])
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func theFoldersBesideTheBareDirectoryOfADotBareLayoutAreItsWorktrees() async throws {
        defer { stop() }
        let project = try fixture.makeDirectory("project")
        let bare = project.appending(path: ".bare")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        try fixture.git("init", "--bare", "--initial-branch=main", in: bare)
        try Data("gitdir: ./.bare\n".utf8).write(to: project.appending(path: ".git"))
        try fixture.seed(bare, as: "project")
        try fixture.git("worktree", "add", "main", "main", in: project)

        let trees = try await client.worktrees(at: project)
        #expect(trees.map(\.checkout) == [.branch("main")])
        #expect(trees.first?.path == project.appending(path: "main").resolvingSymlinksInPath())
        #expect(trees.first?.isMainWorkingTree == false)
        #expect(try await client.branches(at: project) == ["main"])
    }

    // MARK: - branches

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func listsLocalBranchesIncludingSlashedAndPackedOnes() async throws {
        defer { stop() }
        let repository = try fixture.makeRepository("repo")
        try fixture.git("branch", "agent/add-minimap", in: repository)
        try fixture.git("branch", "zeta", in: repository)
        try fixture.git("pack-refs", "--all", in: repository)
        try fixture.git("branch", "alpha", in: repository)

        #expect(try await client.branches(at: repository) == ["agent/add-minimap", "alpha", "main", "zeta"])
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func aBareRepositoryListsItsBranches() async throws {
        defer { stop() }
        let bare = try fixture.makeDirectory("origin.git")
        try fixture.git("init", "--bare", "--initial-branch=main", in: bare)
        try fixture.seed(bare, as: "origin")

        #expect(try await client.branches(at: bare) == ["main"])
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func nonRepositoriesAndLinkedWorktreesHaveNoBranchList() async throws {
        defer { stop() }
        #expect(try await client.branches(at: try fixture.makeDirectory("plain")).isEmpty)

        let repository = try fixture.makeRepository("repo")
        #expect(try await client.branches(at: try addWorktree("linked", to: repository)).isEmpty)
    }

    // MARK: - gitDirectory and checkout

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func aWorkingTreesGitDirectoryIsItsDotGitAndALinkedOnesIsInsideTheMainRepository() async throws {
        defer { stop() }
        let repository = try fixture.makeRepository("repo")
        let linked = try addWorktree("linked", to: repository)

        let main = try #require(try await client.gitDirectory(of: repository))
        let other = try #require(try await client.gitDirectory(of: linked))
        #expect(main.path(percentEncoded: false).hasSuffix("/repo/.git"))
        #expect(other.path(percentEncoded: false).hasSuffix("/repo/.git/worktrees/linked"))
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func foldersThatAreNotWorkingTreesHaveNoGitDirectoryOrCheckout() async throws {
        defer { stop() }
        let bare = try fixture.makeDirectory("origin.git")
        try fixture.git("init", "--bare", in: bare)
        let folders = [try fixture.makeDirectory("plain"), bare, fixture.directory.appending(path: "missing")]

        for folder in folders {
            #expect(try await client.gitDirectory(of: folder) == nil)
            #expect(try await client.checkout(of: folder) == nil)
        }
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func checkoutIsTheBranchOrTheShortCommitWhenDetached() async throws {
        defer { stop() }
        let repository = try fixture.makeRepository("repo")
        #expect(try await client.checkout(of: repository) == .branch("main"))

        let detached = fixture.directory.appending(path: "detached")
        try fixture.git("worktree", "add", "--detach", detached.path(percentEncoded: false), in: repository)
        let sha = try fixture.git("rev-parse", "--short=7", "HEAD", in: repository)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(try await client.checkout(of: detached) == .detached(sha: sha))
    }

    // MARK: - status

    /// Relative paths and their status, which is what the assertions read more
    /// clearly than a dictionary keyed on absolute paths.
    func statuses(in url: URL) async throws -> [String: GitStatus] {
        let status = try await client.status(in: url)
        return Dictionary(uniqueKeysWithValues: status.entries.map {
            (String($0.key.path.dropFirst(status.root.path.count + 1)), $0.value)
        })
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func statusFindsWhatGitIgnoresIncludingNestedRulesAndNegations() async throws {
        defer { stop() }
        let repo = try fixture.makeRepository("repo")
        try write("*.log\nbuild/\n!keep.log\n", to: repo.appending(path: ".gitignore"))
        try write("x", to: repo.appending(path: "build/out.o"))
        try write("*.tmp\n", to: repo.appending(path: "sub/.gitignore"))
        for name in ["debug.log", "keep.log"] { try write("x", to: repo.appending(path: name)) }
        for name in ["x.tmp", "y.txt"] { try write("x", to: repo.appending(path: "sub/\(name)")) }

        let found = try await statuses(in: repo)

        #expect(found["debug.log"] == .ignored)
        #expect(found["sub"] == .untracked)
        #expect(found["sub/x.tmp"] == .ignored)
        #expect(found["keep.log"] == .untracked)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func statusCollapsesIgnoredAndUntrackedFolders() async throws {
        defer { stop() }
        let repo = try fixture.makeRepository("collapsing")
        try write("build/\n", to: repo.appending(path: ".gitignore"))
        for name in ["build", "fresh"] { try write("x", to: repo.appending(path: "\(name)/inside.txt")) }

        let found = try await statuses(in: repo)

        #expect(found["build"] == .ignored)
        #expect(found["fresh"] == .untracked)
        #expect(found["build/inside.txt"] == nil)
        #expect(found["fresh/inside.txt"] == nil)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func statusKeepsStagedAndUnstagedApart() async throws {
        defer { stop() }
        let repo = try fixture.makeRepository("columns")
        try write("one", to: repo.appending(path: "staged.txt"))
        try fixture.git("add", "staged.txt", in: repo)
        try write("two", to: repo.appending(path: "staged.txt"))
        try write("edited", to: repo.appending(path: "README.md"))

        let found = try await statuses(in: repo)

        #expect(found["staged.txt"] == .tracked(staged: .added, unstaged: .modified))
        #expect(found["README.md"] == .tracked(staged: .unchanged, unstaged: .modified))
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func statusReportsADeletedFile() async throws {
        defer { stop() }
        let repo = try fixture.makeRepository("gone")

        try fixture.git("rm", "--quiet", "README.md", in: repo)

        #expect(try await statuses(in: repo)["README.md"] == .tracked(staged: .deleted, unstaged: .unchanged))
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func statusReportsWhereARenameCameFrom() async throws {
        defer { stop() }
        let repo = try fixture.makeRepository("renamed")
        try write("something else entirely", to: repo.appending(path: "moved.txt"))
        try fixture.git("add", ".", in: repo)
        try fixture.git("commit", "-m", "second", in: repo)
        try fixture.git("mv", "moved.txt", "elsewhere.txt", in: repo)

        let found = try await statuses(in: repo)

        #expect(found["elsewhere.txt"] == .tracked(staged: .renamed, unstaged: .unchanged))
        #expect(found["moved.txt"] == .tracked(staged: .renamed, unstaged: .unchanged))
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func statusReadsAPathWithSpacesAndQuotesInIt() async throws {
        defer { stop() }
        let repo = try fixture.makeRepository("awkward")
        let name = #"a "quoted" name.txt"#
        try write("x", to: repo.appending(path: name))

        #expect(try await statuses(in: repo)[name] == .untracked)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func statusIsEmptyOutsideARepository() async throws {
        defer { stop() }
        let plain = try fixture.makeDirectory("plain-status")
        try write("x", to: plain.appending(path: "a.log"))

        #expect(try await client.status(in: plain).entries.isEmpty)
    }

    @Test func anUnreachableDaemonIsAnError() async {
        let client = DaemonGitClient(daemon: LiveDaemonClient(socket: socket, executable: nil, client: "test"))

        await #expect(throws: GitClientError.commandFailed("herderd is not running")) {
            try await client.repositoryKind(at: URL(filePath: "/tmp"))
        }
    }
}
