import Core
import Foundation
import TestSupport
import Testing

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
        let path = URL(filePath: "/tmp/repo/feature")

        try await client.addWorktree(in: repository, at: path, newBranch: "feature", from: "main")

        #expect(client.addedWorktrees == [
            .init(repository: repository, path: path, newBranch: "feature", base: "main")
        ])
    }

    @Test func theStubNamesTheSeededBaseAndRecordsTheFetch() async throws {
        let repository = URL(filePath: "/tmp/repo")
        client.seed(fetchedBase: "origin/main", at: repository)

        #expect(try await client.fetchDefaultBranch(in: repository) == "origin/main")
        #expect(try await client.fetchDefaultBranch(in: URL(filePath: "/tmp/other")) == nil)
        #expect(client.fetchedRepositories.first == repository)
    }

    @Test func theStubCanRefuseToFetch() async {
        client.failFetching(with: "offline")

        await #expect(throws: GitClientError.commandFailed("offline")) {
            try await client.fetchDefaultBranch(in: URL(filePath: "/tmp/repo"))
        }
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
