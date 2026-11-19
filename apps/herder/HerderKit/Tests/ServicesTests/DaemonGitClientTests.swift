import Core
import Darwin
import Foundation
@testable import Services
import Testing

/// The scenarios the `repositoryKind` half of `LiveGitClientTests` holds,
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

    @Test func anUnreachableDaemonIsAnError() async {
        let client = DaemonGitClient(daemon: LiveDaemonClient(socket: socket, executable: nil, client: "test"))

        await #expect(throws: GitClientError.commandFailed("herderd is not running")) {
            try await client.repositoryKind(at: URL(filePath: "/tmp"))
        }
    }
}
