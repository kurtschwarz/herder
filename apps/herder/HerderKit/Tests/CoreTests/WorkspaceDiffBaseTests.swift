import Core
import Foundation
import TestSupport
import Testing

@Suite @MainActor struct WorkspaceDiffBaseTests {
    let files = InMemoryFileClient()
    let git = StubGitClient()
    let store: WorkspaceRegistry
    let root = URL(filePath: "/code/api")

    init() {
        store = WorkspaceRegistry(
            files: files,
            git: git,
            watcher: StubFileWatcherClient(),
            clock: VirtualClockClient(),
            state: InMemoryStateStore()
        )
    }

    func url(_ name: String) -> URL { root.appending(path: name) }

    func start() async throws -> Workspace {
        files.seed(children: [], of: root)
        let workspace = try #require(await store.open(WorkspaceID(PathKey(root))))
        await workspace.refresh()
        return workspace
    }

    @Test func theDefaultIsUncommittedAndReadsHead() async throws {
        git.seed(contents: "old\n", of: url("a.txt"))
        let workspace = try await start()

        #expect(workspace.diffBase == .uncommitted)
        #expect(await workspace.baseContents(of: PathKey(url("a.txt"))) == "old\n")
    }

    @Test func aRefResolvesToItsMergeBase() async throws {
        git.seed(mergeBase: "abc", of: "HEAD~1")
        git.seed(contents: "older\n", of: url("a.txt"), atRevision: "abc")
        git.seed(contents: "head\n", of: url("a.txt"))
        let workspace = try await start()

        await workspace.setDiffBase("HEAD~1")

        #expect(workspace.diffBase == GitDiffBase(ref: "HEAD~1", name: "HEAD~1", revision: "abc", isResolved: true))
        #expect(await workspace.baseContents(of: PathKey(url("a.txt"))) == "older\n")
    }

    @Test func upstreamIsNamedForTheBranchItStandsFor() async throws {
        git.seed(upstream: "origin/main", in: root)
        git.seed(mergeBase: "fork", of: "origin/main")
        let workspace = try await start()

        await workspace.setDiffBase(GitDiffBase.upstream)

        #expect(workspace.diffBase.name == "origin/main")
        #expect(workspace.diffBase.revision == "fork")
    }

    @Test func aRefThatResolvesToNothingFallsBackToHeadAndKeepsTheRef() async throws {
        git.seed(contents: "head\n", of: url("a.txt"))
        let workspace = try await start()

        await workspace.setDiffBase("feature-x")

        #expect(workspace.diffBase.ref == "feature-x")
        #expect(workspace.diffBase.isResolved == false)
        #expect(workspace.diffBase.revision == "HEAD")
        #expect(await workspace.baseContents(of: PathKey(url("a.txt"))) == "head\n")
    }

    @Test func aRefThatComesBackIsFollowedAgain() async throws {
        let workspace = try await start()
        await workspace.setDiffBase("feature-x")
        #expect(workspace.diffBase.isResolved == false)

        git.seed(mergeBase: "back", of: "feature-x")
        await workspace.refresh()

        #expect(workspace.diffBase.isResolved)
        #expect(workspace.diffBase.revision == "back")
    }

    @Test func aFileTheBaseLacksIsAllAdded() async throws {
        git.seed(mergeBase: "abc", of: "main")
        git.seed(changedFiles: [GitChangedFile(path: "new.txt", status: .added, insertions: 2)], since: "abc")
        git.seed(status: ["new.txt": .tracked(staged: .unchanged, unstaged: .modified)], in: root)
        let workspace = try await start()
        await workspace.setDiffBase("main")

        #expect(await workspace.baseContents(of: PathKey(url("new.txt"))) == "")
    }

    @Test func aRenamedFileIsComparedWithWhatItWasCalled() async throws {
        git.seed(mergeBase: "abc", of: "main")
        git.seed(
            changedFiles: [GitChangedFile(path: "new.txt", previousPath: "old.txt", status: .renamed)],
            since: "abc"
        )
        git.seed(contents: "was\n", of: url("old.txt"), atRevision: "abc")
        git.seed(status: ["new.txt": .tracked(staged: .renamed, unstaged: .unchanged)], in: root)
        let workspace = try await start()
        await workspace.setDiffBase("main")

        #expect(await workspace.baseContents(of: PathKey(url("new.txt"))) == "was\n")
    }

    @Test func untrackedIgnoredAndConflictedFilesHaveNoBase() async throws {
        git.seed(mergeBase: "abc", of: "main")
        git.seed(status: ["u.txt": .untracked, "i.txt": .ignored, "c.txt": .unmerged], in: root)
        for name in ["u.txt", "i.txt", "c.txt"] { git.seed(contents: "x", of: url(name), atRevision: "abc") }
        let workspace = try await start()
        await workspace.setDiffBase("main")

        for name in ["u.txt", "i.txt", "c.txt"] {
            #expect(await workspace.baseContents(of: PathKey(url(name))) == nil)
        }
    }

    @Test func theChangedFilesAreThoseSinceTheResolvedBaseWithoutConflicts() async throws {
        git.seed(mergeBase: "abc", of: "main")
        git.seed(
            changedFiles: [
                GitChangedFile(path: "a.txt", status: .modified),
                GitChangedFile(path: "c.txt", status: .modified),
            ],
            since: "abc"
        )
        git.seed(status: ["c.txt": .unmerged], in: root)
        let workspace = try await start()
        await workspace.setDiffBase("main")

        #expect(await workspace.changedFiles().map(\.path) == ["a.txt"])
    }

    @Test func theChoiceIsWrittenToTheSnapshotAndComesBack() async throws {
        let workspace = try await start()
        #expect(workspace.snapshot.diffBase == nil)

        await workspace.setDiffBase("HEAD~1")
        let snapshot = workspace.snapshot
        #expect(snapshot.diffBase == "HEAD~1")

        let other = try #require(await store.open(WorkspaceID(PathKey(URL(filePath: "/code/other")))))
        other.restore(from: snapshot)
        #expect(other.diffBase.ref == "HEAD~1")
    }

    @Test func anOldSnapshotDecodesToUncommitted() throws {
        let id = WorkspaceID(PathKey(root))
        let encoded = try JSONEncoder().encode(WorkspaceSnapshot(id: id))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["diffBase"] = nil
        let old = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(WorkspaceSnapshot.self, from: old)

        #expect(decoded.diffBase == nil)
    }

    @Test func changeSummaryAgainstARefUsesItsMergeBase() async throws {
        git.seed(mergeBase: "abc", of: "HEAD~1")
        git.seed(shortstat: GitChangeSummary(insertions: 4, deletions: 2), since: "abc")
        let workspace = try await start()

        #expect(await workspace.changeSummary(against: "HEAD~1") == GitChangeSummary(insertions: 4, deletions: 2))
        #expect(await workspace.changeSummary(against: "nope") == nil)
    }
}
