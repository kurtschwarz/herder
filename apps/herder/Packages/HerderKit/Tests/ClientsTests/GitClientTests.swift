import Clients
import ClientsTestSupport
import Foundation
import Testing

/// Builds real repositories on disk with real `git`, so the expected answers come
/// from git itself rather than from the same layout rules the client applies.
/// Tests are not sandboxed, so running `git` here is safe; the client under test
/// deliberately does not.
@Suite struct LiveGitClientTests {
    let directory: URL
    let client = LiveGitClient()

    init() throws {
        directory = URL.temporaryDirectory
            .appending(path: "LiveGitClientTests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @discardableResult
    func git(_ arguments: String..., in url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = url
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            Issue.record("git \(arguments.joined(separator: " ")) failed: \(output)")
            throw CocoaError(.fileNoSuchFile)
        }
        return output
    }

    func makeDirectory(_ name: String) throws -> URL {
        let url = directory.appending(path: name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A repository with one commit, so `git worktree add` has something to branch.
    func makeRepository(_ name: String) throws -> URL {
        let url = try makeDirectory(name)
        try git("init", "--initial-branch=main", in: url)
        try git("config", "user.email", "test@example.com", in: url)
        try git("config", "user.name", "Test", in: url)
        try Data("x".utf8).write(to: url.appending(path: "README.md"))
        try git("add", ".", in: url)
        try git("commit", "-m", "first", in: url)
        return url
    }

    @Test func plainFolderIsNotARepository() async throws {
        let url = try makeDirectory("plain")
        #expect(try await client.repositoryKind(at: url) == .notARepository)
    }

    @Test func repositoryRootIsAMainWorkingTree() async throws {
        let url = try makeRepository("repo")
        #expect(try await client.repositoryKind(at: url) == .mainWorkingTree)
    }

    @Test func subdirectoryOfARepositoryIsNotARepository() async throws {
        let repository = try makeRepository("repo")
        let nested = repository.appending(path: "src")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        #expect(try await client.repositoryKind(at: nested) == .notARepository)
    }

    @Test func bareRepositoryIsRecognised() async throws {
        let url = try makeDirectory("api.git")
        try git("init", "--bare", in: url)
        #expect(try await client.repositoryKind(at: url) == .bare)
    }

    @Test func linkedWorktreeReportsItsMainRepository() async throws {
        let repository = try makeRepository("repo")
        let worktree = directory.appending(path: "feature")
        try git("worktree", "add", worktree.path(percentEncoded: false), "-b", "feature", in: repository)

        let kind = try await client.repositoryKind(at: worktree)
        #expect(kind == .linkedWorktree(mainRepository: repository.resolvingSymlinksInPath()))
    }

    @Test func worktreeOfABareRepositoryReportsTheBareDirectory() async throws {
        let bare = try makeDirectory("origin.git")
        try git("init", "--bare", "--initial-branch=main", in: bare)

        // A bare repo has no commits yet, so seed one through a temporary clone.
        let seed = try makeDirectory("seed")
        try git("clone", bare.path(percentEncoded: false), seed.path(percentEncoded: false), in: directory)
        try git("config", "user.email", "test@example.com", in: seed)
        try git("config", "user.name", "Test", in: seed)
        try Data("x".utf8).write(to: seed.appending(path: "README.md"))
        try git("add", ".", in: seed)
        try git("commit", "-m", "first", in: seed)
        try git("push", "origin", "main", in: seed)

        let worktree = directory.appending(path: "bare-feature")
        try git("worktree", "add", worktree.path(percentEncoded: false), "main", in: bare)

        let kind = try await client.repositoryKind(at: worktree)
        #expect(kind == .linkedWorktree(mainRepository: bare.resolvingSymlinksInPath()))
    }

    @Test func missingFolderIsNotARepository() async throws {
        let url = directory.appending(path: "nothing-here")
        #expect(try await client.repositoryKind(at: url) == .notARepository)
    }

    // MARK: - worktrees

    @Test func repositoryWithoutWorktreesListsOnlyItsMainWorkingTree() async throws {
        let repository = try makeRepository("repo")
        let trees = try await client.worktrees(at: repository)
        #expect(trees.count == 1)
        #expect(trees.first?.path == repository.resolvingSymlinksInPath())
        #expect(trees.first?.checkout == .branch("main"))
        #expect(trees.first?.isMainWorkingTree == true)
    }

    @Test func worktreesReportWhenTheyLastChanged() async throws {
        let repository = try makeRepository("repo")
        let linked = directory.appending(path: "feature")
        try git("worktree", "add", linked.path(percentEncoded: false), "-b", "feature", in: repository)

        let trees = try await client.worktrees(at: repository)

        for tree in trees {
            let activity = try #require(tree.lastActivity)
            #expect(abs(activity.timeIntervalSinceNow) < 120)
        }
    }

    // MARK: - branches

    @Test func listsLocalBranchesIncludingSlashedAndPackedOnes() async throws {
        let repository = try makeRepository("repo")
        try git("branch", "agent/add-minimap", in: repository)
        try git("branch", "zeta", in: repository)
        try git("pack-refs", "--all", in: repository)
        try git("branch", "alpha", in: repository)

        let branches = try await client.branches(at: repository)

        #expect(branches == ["agent/add-minimap", "alpha", "main", "zeta"])
    }

    @Test func aBareRepositoryListsItsBranches() async throws {
        let bare = try makeDirectory("origin.git")
        try git("init", "--bare", "--initial-branch=main", in: bare)
        let seed = try makeDirectory("seed")
        try git("clone", bare.path(percentEncoded: false), seed.path(percentEncoded: false), in: directory)
        try git("config", "user.email", "test@example.com", in: seed)
        try git("config", "user.name", "Test", in: seed)
        try Data("x".utf8).write(to: seed.appending(path: "README.md"))
        try git("add", ".", in: seed)
        try git("commit", "-m", "first", in: seed)
        try git("push", "origin", "main", in: seed)

        #expect(try await client.branches(at: bare) == ["main"])
    }

    @Test func nonRepositoriesAndLinkedWorktreesHaveNoBranchList() async throws {
        #expect(try await client.branches(at: try makeDirectory("plain")).isEmpty)

        let repository = try makeRepository("repo")
        let linked = directory.appending(path: "linked")
        try git("worktree", "add", linked.path(percentEncoded: false), "-b", "linked", in: repository)
        #expect(try await client.branches(at: linked).isEmpty)
    }

    // MARK: - addWorktree

    @Test func addingAWorktreeCreatesItOnANewBranch() async throws {
        let repository = try makeRepository("repo")
        let path = GitWorktreeLocation.path(
            forBranch: "agent/add-minimap",
            inRepository: repository,
            kind: .mainWorkingTree
        )!

        try await client.addWorktree(in: repository, at: path, newBranch: "agent/add-minimap", from: "main")

        let trees = try await client.worktrees(at: repository)
        #expect(trees.map(\.checkout) == [.branch("main"), .branch("agent/add-minimap")])
        #expect(trees.last?.path == path.resolvingSymlinksInPath())
        #expect(path.lastPathComponent == "agent-add-minimap")
    }

    @Test func theWorktreeFolderStaysOutOfGitStatus() async throws {
        let repository = try makeRepository("repo")
        let path = GitWorktreeLocation.path(forBranch: "feature", inRepository: repository, kind: .mainWorkingTree)!

        try await client.addWorktree(in: repository, at: path, newBranch: "feature", from: "main")
        try await client.addWorktree(
            in: repository,
            at: GitWorktreeLocation.path(forBranch: "other", inRepository: repository, kind: .mainWorkingTree)!,
            newBranch: "other",
            from: "main"
        )

        #expect(try git("status", "--porcelain", in: repository).isEmpty)
        let exclude = try String(contentsOf: repository.appending(path: ".git/info/exclude"), encoding: .utf8)
        #expect(exclude.components(separatedBy: ".worktrees/").count == 2)
    }

    @Test func addingToABareRepositoryPutsTheWorktreeBesideTheRest() async throws {
        let bare = try makeDirectory("origin.git")
        try git("init", "--bare", "--initial-branch=main", in: bare)
        let seed = try makeDirectory("seed")
        try git("clone", bare.path(percentEncoded: false), seed.path(percentEncoded: false), in: directory)
        try git("config", "user.email", "test@example.com", in: seed)
        try git("config", "user.name", "Test", in: seed)
        try Data("x".utf8).write(to: seed.appending(path: "README.md"))
        try git("add", ".", in: seed)
        try git("commit", "-m", "first", in: seed)
        try git("push", "origin", "main", in: seed)

        let path = GitWorktreeLocation.path(forBranch: "feature", inRepository: bare, kind: .bare)!
        try await client.addWorktree(in: bare, at: path, newBranch: "feature", from: "main")

        let trees = try await client.worktrees(at: bare)
        #expect(trees.map(\.checkout) == [.branch("feature")])
        #expect(path.deletingLastPathComponent().standardizedFileURL == bare.standardizedFileURL)
    }

    @Test func gitsRefusalComesBackAsTheError() async throws {
        let repository = try makeRepository("repo")
        let path = GitWorktreeLocation.path(forBranch: "main", inRepository: repository, kind: .mainWorkingTree)!

        let error = await #expect(throws: GitClientError.self) {
            try await client.addWorktree(in: repository, at: path, newBranch: "main", from: "main")
        }

        guard case .commandFailed(let message)? = error else {
            Issue.record("expected commandFailed")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test func linkedWorktreesFollowMainAndSortByBranch() async throws {
        let repository = try makeRepository("repo")
        for branch in ["zeta", "alpha"] {
            let path = directory.appending(path: branch)
            try git("worktree", "add", path.path(percentEncoded: false), "-b", branch, in: repository)
        }

        let trees = try await client.worktrees(at: repository)
        #expect(trees.map(\.checkout) == [.branch("main"), .branch("alpha"), .branch("zeta")])
        #expect(trees.map(\.isMainWorkingTree) == [true, false, false])
        #expect(trees[1].path == directory.appending(path: "alpha").resolvingSymlinksInPath())
    }

    @Test func detachedWorktreeShowsShortShaAndSortsLast() async throws {
        let repository = try makeRepository("repo")
        let detached = directory.appending(path: "detached")
        try git("worktree", "add", "--detach", detached.path(percentEncoded: false), in: repository)
        let branch = directory.appending(path: "beta")
        try git("worktree", "add", branch.path(percentEncoded: false), "-b", "beta", in: repository)

        let sha = try git("rev-parse", "--short=7", "HEAD", in: repository)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trees = try await client.worktrees(at: repository)
        #expect(trees.map(\.checkout) == [.branch("main"), .branch("beta"), .detached(sha: sha)])
    }

    @Test func bareRepositoryContributesOnlyItsWorktrees() async throws {
        let bare = try makeDirectory("origin.git")
        try git("init", "--bare", "--initial-branch=main", in: bare)
        let seed = try makeDirectory("seed")
        try git("clone", bare.path(percentEncoded: false), seed.path(percentEncoded: false), in: directory)
        try git("config", "user.email", "test@example.com", in: seed)
        try git("config", "user.name", "Test", in: seed)
        try Data("x".utf8).write(to: seed.appending(path: "README.md"))
        try git("add", ".", in: seed)
        try git("commit", "-m", "first", in: seed)
        try git("push", "origin", "main", in: seed)

        let worktree = directory.appending(path: "bare-main")
        try git("worktree", "add", worktree.path(percentEncoded: false), "main", in: bare)

        let trees = try await client.worktrees(at: bare)
        #expect(trees.count == 1)
        #expect(trees.first?.checkout == .branch("main"))
        #expect(trees.first?.isMainWorkingTree == false)
    }

    @Test func worktreeWhoseFolderWasDeletedIsSkipped() async throws {
        let repository = try makeRepository("repo")
        let gone = directory.appending(path: "gone")
        try git("worktree", "add", gone.path(percentEncoded: false), "-b", "gone", in: repository)
        try FileManager.default.removeItem(at: gone)

        let trees = try await client.worktrees(at: repository)
        #expect(trees.map(\.checkout) == [.branch("main")])
    }

    @Test func nonRepositoriesAndLinkedWorktreesHaveNoWorktrees() async throws {
        let plain = try makeDirectory("plain")
        #expect(try await client.worktrees(at: plain).isEmpty)

        let repository = try makeRepository("repo")
        let linked = directory.appending(path: "linked")
        try git("worktree", "add", linked.path(percentEncoded: false), "-b", "linked", in: repository)
        #expect(try await client.worktrees(at: linked).isEmpty)
    }
}

/// The fake has to behave like the real thing, or tests written against it lie.
@Suite struct StubGitClientTests {
    let client = StubGitClient()

    @Test func unknownPathsAreNotRepositories() async throws {
        #expect(try await client.repositoryKind(at: URL(filePath: "/tmp/whatever")) == .notARepository)
    }

    @Test func seededPathsReportTheirKind() async throws {
        let url = URL(filePath: "/tmp/repo")
        client.seed(url, .mainWorkingTree)
        #expect(try await client.repositoryKind(at: url) == .mainWorkingTree)
    }

    @Test func theStubRecordsWhatWasAdded() async throws {
        let repository = URL(filePath: "/tmp/repo")
        let path = URL(filePath: "/tmp/repo/.worktrees/feature")

        try await client.addWorktree(in: repository, at: path, newBranch: "feature", from: "main")

        #expect(client.addedWorktrees == [
            .init(repository: repository, path: path, newBranch: "feature", base: "main")
        ])
    }

    @Test func theStubCanRefuseToAdd() async {
        client.failAddingWorktrees(with: "nope")

        await #expect(throws: GitClientError.commandFailed("nope")) {
            try await client.addWorktree(
                in: URL(filePath: "/tmp/repo"),
                at: URL(filePath: "/tmp/x"),
                newBranch: "x",
                from: "main"
            )
        }
    }

    @Test func seededBranchesComeBack() async throws {
        let url = URL(filePath: "/tmp/repo")
        client.seed(branches: ["a", "main"], at: url)
        #expect(try await client.branches(at: url) == ["a", "main"])
    }

    @Test func seededWorktreesComeBackInOrder() async throws {
        let url = URL(filePath: "/tmp/repo")
        let trees = [GitWorktree(path: url, checkout: .branch("main"), isMainWorkingTree: true)]
        client.seed(worktrees: trees, at: url)
        #expect(try await client.worktrees(at: url) == trees)
        #expect(try await client.worktrees(at: URL(filePath: "/tmp/other")).isEmpty)
    }
}
