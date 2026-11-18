import Core
import Foundation
import TestSupport
import Testing

@testable import DiffBaseFeature

@Suite @MainActor struct DiffBaseModelTests {
    let git = StubGitClient()
    let root = URL(filePath: "/code/api")
    let store: WorkspaceRegistry

    init() {
        store = WorkspaceRegistry(
            files: InMemoryFileClient(),
            git: git,
            watcher: StubFileWatcherClient(),
            clock: VirtualClockClient(),
            state: InMemoryStateStore()
        )
    }

    func start() async throws -> Workspace {
        let workspace = try #require(await store.open(WorkspaceID(PathKey(root))))
        await workspace.refresh()
        return workspace
    }

    @Test func thePickerCountsEachPresetWhenItLoads() async throws {
        git.seed(upstream: "origin/main", in: root)
        git.seed(mergeBase: "up", of: "origin/main")
        git.seed(mergeBase: "prev", of: "HEAD~1")
        git.seed(shortstat: GitChangeSummary(insertions: 1, deletions: 2), since: "HEAD")
        git.seed(shortstat: GitChangeSummary(insertions: 30, deletions: 4), since: "up")
        git.seed(shortstat: GitChangeSummary(insertions: 5, deletions: 6), since: "prev")
        let model = DiffBasePickerModel(workspace: try await start())

        await model.load()

        #expect(model.upstreamName == "origin/main")
        #expect(model.counts[.uncommitted] == GitChangeSummary(insertions: 1, deletions: 2))
        #expect(model.counts[.upstream] == GitChangeSummary(insertions: 30, deletions: 4))
        #expect(model.counts[.previousCommit] == GitChangeSummary(insertions: 5, deletions: 6))
        #expect(model.presets == [.uncommitted, .upstream, .previousCommit])
    }

    @Test func previousCommitIsHiddenOnARootCommit() async throws {
        let model = DiffBasePickerModel(workspace: try await start())

        await model.load()

        #expect(model.presets == [.uncommitted, .upstream])
    }

    @Test func pickingARowChangesTheBaseAndASearchedOneShowsAsCustom() async throws {
        git.seed(mergeBase: "abc", of: "v1.0")
        git.seed(refs: [GitRef(name: "v1.0", kind: .tag, date: .now)], in: root)
        let workspace = try await start()
        let model = DiffBasePickerModel(workspace: workspace)
        await model.load()
        #expect(model.customRef == nil)

        await model.pick("v1.0")

        #expect(workspace.diffBase.revision == "abc")
        #expect(model.customRef == "v1.0")
        #expect(model.customKind == "Tag")
    }

    @Test func returnPicksAPastedSHA() async throws {
        let sha = String(repeating: "c", count: 40)
        git.seed(commit: GitCommit(sha: sha, subject: "s", date: .now), matching: "cccc")
        git.seed(mergeBase: sha, of: sha)
        let workspace = try await start()
        let model = DiffBasePickerModel(workspace: workspace)
        model.query = "cccc"

        #expect(await model.submit())
        #expect(workspace.diffBase.ref == sha)
    }

    @Test func theChangedFilesFollowTheBase() async throws {
        git.seed(changedFiles: [GitChangedFile(path: "a.txt", status: .modified)], since: "HEAD")
        git.seed(mergeBase: "abc", of: "main")
        git.seed(changedFiles: [
            GitChangedFile(path: "a.txt", status: .modified),
            GitChangedFile(path: "b.txt", status: .added),
        ], since: "abc")
        let workspace = try await start()
        let model = ChangedFilesModel(workspace: workspace)
        await model.start()
        #expect(model.files?.map(\.path) == ["a.txt"])

        await workspace.setDiffBase("main")

        for _ in 0..<200 where model.files?.count != 2 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(model.files?.map(\.path) == ["a.txt", "b.txt"])
        model.stop()
    }

    @Test func aMissingRefIsNamedInTheWarning() {
        let base = GitDiffBase(ref: "feature-x", name: "feature-x", revision: "HEAD", isResolved: false)
        #expect(DiffBaseName.warning(for: base) == "feature-x not found, showing uncommitted changes")
        #expect(DiffBaseName.display(String(repeating: "a", count: 40)) == "aaaaaaa")
    }
}
