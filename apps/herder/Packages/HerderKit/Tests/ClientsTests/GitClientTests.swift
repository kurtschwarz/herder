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
        #expect(trees == [
            GitWorktree(
                path: repository.resolvingSymlinksInPath(),
                checkout: .branch("main"),
                isMainWorkingTree: true
            )
        ])
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

    @Test func seededWorktreesComeBackInOrder() async throws {
        let url = URL(filePath: "/tmp/repo")
        let trees = [GitWorktree(path: url, checkout: .branch("main"), isMainWorkingTree: true)]
        client.seed(worktrees: trees, at: url)
        #expect(try await client.worktrees(at: url) == trees)
        #expect(try await client.worktrees(at: URL(filePath: "/tmp/other")).isEmpty)
    }
}
