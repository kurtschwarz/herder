import Core
import Foundation
@testable import Services
import Testing

/// The diff and history scenarios of the old `LiveGitClient` tests (`changeSummary`,
/// `mergeBase`, `upstream`, `shortstat`, `changedFiles`, `refs`, `recentCommits`,
/// `commit`, `contents`), against a live `herderd`. `packages/herderd/tests/history.rs`
/// runs the same scenarios against the daemon alone.
extension DaemonGitClientTests {
    func sha(_ name: String, in repo: URL) throws -> String {
        try fixture.git("rev-parse", name, in: repo).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - contents

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func contentsAreTheCommittedTextNotTheWorkingOrStagedOne() async throws {
        defer { stop() }
        let repo = try fixture.makeRepository("committed")
        let file = repo.appending(path: "sub/file.txt")
        try write("committed\n", to: file)
        try fixture.git("add", ".", in: repo)
        try fixture.git("commit", "-m", "second", in: repo)
        try write("staged\n", to: file)
        try fixture.git("add", ".", in: repo)
        try write("working\n", to: file)

        #expect(try await client.contents(of: file, atRevision: "HEAD", in: repo) == "committed\n")
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func contentsAreNilForAFileNotInTheRevision() async throws {
        defer { stop() }
        let repo = try fixture.makeRepository("not-committed")
        try write("new\n", to: repo.appending(path: "new.txt"))
        try fixture.git("add", "new.txt", in: repo)

        #expect(try await client.contents(of: repo.appending(path: "new.txt"), atRevision: "HEAD", in: repo) == nil)
        #expect(try await client.contents(of: repo.appending(path: "nope.txt"), atRevision: "HEAD", in: repo) == nil)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func contentsAreNilForAFileThatIsNotUTF8() async throws {
        defer { stop() }
        let repo = try fixture.makeRepository("binary")
        try Data([0xFF, 0xFE, 0x00, 0x80]).write(to: repo.appending(path: "blob.bin"))
        try fixture.git("add", ".", in: repo)
        try fixture.git("commit", "-m", "binary", in: repo)

        #expect(try await client.contents(of: repo.appending(path: "blob.bin"), atRevision: "HEAD", in: repo) == nil)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func contentsAreNilOutsideARepository() async throws {
        defer { stop() }
        let plain = try fixture.makeDirectory("plain-contents")
        try write("x", to: plain.appending(path: "a.txt"))

        #expect(try await client.contents(of: plain.appending(path: "a.txt"), atRevision: "HEAD", in: plain) == nil)
    }

    // MARK: - changeSummary

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func changeSummaryCountsCommittedAndUncommittedLinesAgainstTheMergeBase() async throws {
        defer { stop() }
        let repo = try fixture.makeRepository("changes")
        try fixture.git("checkout", "-b", "feature", in: repo)
        try write("x\na\nb\n", to: repo.appending(path: "README.md"))
        try fixture.git("commit", "-am", "more", in: repo)
        // Main moves on after the fork, which the merge-base ignores.
        try fixture.git("checkout", "main", in: repo)
        try write("x\nmain only\n", to: repo.appending(path: "other.txt"))
        try fixture.git("add", ".", in: repo)
        try fixture.git("commit", "-m", "main moves", in: repo)
        try fixture.git("checkout", "feature", in: repo)
        // Staged and unstaged, both tracked.
        try write("a\nb\nc\nd\n", to: repo.appending(path: "README.md"))
        try write("new\n", to: repo.appending(path: "added.txt"))
        try fixture.git("add", "added.txt", in: repo)
        // Untracked: not counted.
        try write("ignored\nby\nthe\ncount\n", to: repo.appending(path: "untracked.txt"))

        // README: x -> a b c d is 4 inserted, 1 deleted; added.txt: 1 inserted.
        #expect(try await client.changeSummary(in: repo) == GitChangeSummary(insertions: 5, deletions: 1))
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func changeSummaryFallsBackToMaster() async throws {
        defer { stop() }
        let repo = try fixture.makeDirectory("master-repo")
        try fixture.git("init", "--initial-branch=master", in: repo)
        try fixture.configureIdentity(in: repo)
        try fixture.commitSomething(in: repo)
        try write("x\ny\n", to: repo.appending(path: "README.md"))

        #expect(try await client.changeSummary(in: repo) == GitChangeSummary(insertions: 2, deletions: 1))
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func changeSummaryIsNilWithoutADefaultBranch() async throws {
        defer { stop() }
        let repo = try fixture.makeDirectory("trunk-repo")
        try fixture.git("init", "--initial-branch=trunk", in: repo)
        try fixture.configureIdentity(in: repo)
        try fixture.commitSomething(in: repo)

        #expect(try await client.changeSummary(in: repo) == nil)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func changeSummaryIsNilOutsideAWorktree() async throws {
        defer { stop() }
        #expect(try await client.changeSummary(in: try fixture.makeDirectory("plain-changes")) == nil)
    }

    // MARK: - mergeBase and upstream

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func mergeBaseOfAnAncestorIsTheAncestorAndOfNothingIsNil() async throws {
        defer { stop() }
        let repo = try fixture.makeRepository("merge-base")
        try write("x\na\n", to: repo.appending(path: "README.md"))
        try fixture.git("commit", "-am", "second", in: repo)
        let first = try sha("HEAD~1", in: repo)

        #expect(try await client.mergeBase(of: "HEAD~1", in: repo) == first)
        #expect(try await client.mergeBase(of: "nope", in: repo) == nil)
        #expect(try await client.mergeBase(of: "--output=x", in: repo) == nil)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func upstreamIsWhatTheBranchTracksElseTheDefaultBranch() async throws {
        defer { stop() }
        let origin = try fixture.makeRepository("origin")
        try fixture.git("branch", "release", in: origin)
        let clone = fixture.directory.appending(path: "clone")
        try fixture.git("clone", origin.path(percentEncoded: false), clone.path(percentEncoded: false), in: fixture.directory)
        try fixture.git("checkout", "-b", "local-only", in: clone)

        #expect(try await client.upstream(in: clone) == "origin/main")

        try fixture.git("checkout", "--track", "origin/release", in: clone)
        #expect(try await client.upstream(in: clone) == "origin/release")
    }

    // MARK: - shortstat and changedFiles

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func shortstatCountsStagedAndUnstagedSinceACommit() async throws {
        defer { stop() }
        let repo = try fixture.makeRepository("shortstat")
        try write("a\nb\n", to: repo.appending(path: "README.md"))
        try write("new\n", to: repo.appending(path: "added.txt"))
        try fixture.git("add", "added.txt", in: repo)

        #expect(try await client.shortstat(since: "HEAD", in: repo) == GitChangeSummary(insertions: 3, deletions: 1))
        #expect(try await client.shortstat(since: "nope", in: repo) == nil)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func changedFilesListTrackedChangesWithCountsAndLeaveUntrackedOut() async throws {
        defer { stop() }
        let repo = try fixture.makeRepository("changed-files")
        try write("a\nb\nc\n", to: repo.appending(path: "README.md"))
        try write("new\n", to: repo.appending(path: "added.txt"))
        try fixture.git("add", "added.txt", in: repo)
        try write("loose\n", to: repo.appending(path: "untracked.txt"))

        let files = try await client.changedFiles(since: "HEAD", in: repo)

        #expect(files.map(\.path) == ["added.txt", "README.md"])
        #expect(files.map(\.status) == [.added, .modified])
        #expect(files[0].insertions == 1)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func changedFilesPairARenameWithWhereItCameFrom() async throws {
        defer { stop() }
        let repo = try fixture.makeRepository("renamed-files")
        try write("something else entirely\nwith two lines\n", to: repo.appending(path: "moved.txt"))
        try fixture.git("add", ".", in: repo)
        try fixture.git("commit", "-m", "second", in: repo)
        try fixture.git("mv", "moved.txt", "elsewhere.txt", in: repo)

        let files = try await client.changedFiles(since: "HEAD", in: repo)

        #expect(files == [GitChangedFile(
            path: "elsewhere.txt", previousPath: "moved.txt", status: .renamed, insertions: 0, deletions: 0
        )])
    }

    // MARK: - refs and commits

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func refsAndCommitsAreListedAndAShaAbbreviationResolves() async throws {
        defer { stop() }
        let repo = try fixture.makeRepository("refs")
        try fixture.git("tag", "v1", in: repo)
        try fixture.git("branch", "other", in: repo)
        let sha = try sha("HEAD", in: repo)

        let refs = try await client.refs(in: repo)
        #expect(Set(refs.map(\.name)) == ["main", "other", "v1"])
        #expect(refs.first { $0.name == "v1" }?.kind == .tag)
        #expect(try await client.recentCommits(limit: 5, in: repo).map(\.sha) == [sha])
        #expect(try await client.commit(matching: String(sha.prefix(7)), in: repo)?.sha == sha)
        #expect(try await client.commit(matching: "feedbeef", in: repo) == nil)
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func recentCommitsStopAtTheLimitNewestFirst() async throws {
        defer { stop() }
        let repo = try fixture.makeRepository("log")
        for n in 0..<3 {
            try write("\(n)", to: repo.appending(path: "README.md"))
            try fixture.git("commit", "-am", "change \(n)", in: repo)
        }

        #expect(try await client.recentCommits(limit: 2, in: repo).map(\.subject) == ["change 2", "change 1"])
    }

    @Test(.enabled(if: LiveDaemonClientTests.built))
    func nothingAnswersOutsideAWorkingTree() async throws {
        defer { stop() }
        let plain = try fixture.makeDirectory("plain-history")

        #expect(try await client.refs(in: plain).isEmpty)
        #expect(try await client.recentCommits(limit: 5, in: plain).isEmpty)
        #expect(try await client.commit(matching: "HEAD", in: plain) == nil)
        #expect(try await client.upstream(in: plain) == nil)
        #expect(try await client.mergeBase(of: "HEAD", in: plain) == nil)
        #expect(try await client.changedFiles(since: "HEAD", in: plain).isEmpty)
    }
}
