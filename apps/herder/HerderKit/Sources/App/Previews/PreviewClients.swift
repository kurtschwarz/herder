#if DEBUG
import Core
import Foundation
import Services

/// Does-nothing `FileClient` for SwiftUI previews. Debug-only so it never reaches a
/// release build; tests use `InMemoryFileClient` from `ClientsTestSupport` instead.
struct PreviewFileClient: FileClient {
    func read(_ path: String) async throws -> String { "" }
    func read(_ path: String, maxBytes: Int) async throws -> String { "" }
    func write(_ contents: String, to path: String) async throws {}
    func exists(_ path: String) async -> Bool { true }
    func move(_ source: URL, to destination: URL) async throws {}
    func create(_ url: URL, isDirectory: Bool) async throws {}
    func delete(_ url: URL, permanently: Bool) async throws {}
    func children(of url: URL) async throws -> [DirectoryEntry] {
        [
            DirectoryEntry(url: url.appending(path: "Sources"), isDirectory: true),
            DirectoryEntry(url: url.appending(path: "Package.swift"), isDirectory: false),
            DirectoryEntry(url: url.appending(path: "README.md"), isDirectory: false),
        ]
    }
}

/// Previews cannot link `ClientsTestSupport`, so they get their own throwaway
/// bookmark and git clients. Neither touches the sandbox or the disk.
struct PreviewBookmarkClient: BookmarkClient {
    func makeBookmark(for url: URL) throws -> Data { Data(url.path(percentEncoded: false).utf8) }

    func resolve(_ bookmark: Data) throws -> ResolvedBookmark {
        ResolvedBookmark(url: URL(filePath: String(decoding: bookmark, as: UTF8.self)), isStale: false)
    }

    func startAccessing(_ url: URL) -> Bool { true }
    func stopAccessing(_ url: URL) {}
}

struct PreviewFolderPickerClient: FolderPickerClient {
    @MainActor
    func pickFolder(startingAt: URL?) async -> URL? { URL(filePath: "/preview/my-project") }
}

struct PreviewGitClient: GitClient {
    func branches(at url: URL) async throws -> [String] { ["feature", "main"] }
    func addWorktree(in repository: URL, at path: URL, newBranch: String, from base: String) async throws {}
    func fetchDefaultBranch(in repository: URL) async throws -> String? { "origin/main" }
    func repositoryKind(at url: URL) async throws -> GitRepositoryKind { .mainWorkingTree }
    func gitDirectory(of url: URL) async throws -> URL? { url.appending(path: ".git") }
    func checkout(of url: URL) async throws -> GitWorktree.Checkout? { .branch("main") }
    func status(in worktree: URL) async throws -> GitWorktreeStatus {
        let root = PathKey(worktree)
        return GitWorktreeStatus(root: root, entries: [root.appending("Package.swift"): .ignored])
    }
    func changeSummary(in worktree: URL) async throws -> GitChangeSummary? {
        GitChangeSummary(insertions: 107, deletions: 19)
    }
    func contents(of file: URL, atRevision revision: String, in worktree: URL) async throws -> String? { nil }
    func mergeBase(of ref: String, in worktree: URL) async throws -> String? { nil }
    func upstream(in worktree: URL) async throws -> String? { "origin/main" }
    func shortstat(since sha: String, in worktree: URL) async throws -> GitChangeSummary? { nil }
    func changedFiles(since sha: String, in worktree: URL) async throws -> [GitChangedFile] { [] }
    func refs(in worktree: URL) async throws -> [GitRef] { [] }
    func recentCommits(limit: Int, in worktree: URL) async throws -> [GitCommit] { [] }
    func commit(matching revision: String, in worktree: URL) async throws -> GitCommit? { nil }
    func worktrees(at url: URL) async throws -> [GitWorktree] {
        [
            GitWorktree(path: url, checkout: .branch("main"), isMainWorkingTree: true),
            GitWorktree(path: url.appending(path: "feature"), checkout: .branch("feature"), isMainWorkingTree: false),
        ]
    }
}

struct PreviewFileWatcherClient: FileWatcherClient {
    func watch(_ roots: [URL], from position: FileWatcherPosition?) -> AsyncStream<FileChangeBatch> {
        AsyncStream { $0.finish() }
    }
}

extension AppEnvironment {
    /// An app environment over fakes, with two repositories already adopted and
    /// listed by the window that appears.
    ///
    /// State goes to a throwaway directory under the system temporary
    /// directory, one per preview, so a canvas never reads or writes the real
    /// app's files.
    @MainActor static var preview: AppEnvironment {
        let environment = AppEnvironment(
            files: PreviewFileClient(),
            bookmarks: PreviewBookmarkClient(),
            git: PreviewGitClient(),
            folderPicker: PreviewFolderPickerClient(),
            watcher: PreviewFileWatcherClient(),
            clock: LiveClockClient(),
            persistence: PersistenceStack.temporary()
        )

        // Adopted into the pool, then listed by a window the preview's own
        // window adopts: a repository no window lists is not on screen.
        Task {
            var members: [RepositoryMembership] = []
            for name in ["agent-editor", "herder"] {
                let url = URL(filePath: "/preview/\(name)")
                if let repository = try? await environment.repositories.add(url: url, name: name) {
                    members.append(RepositoryMembership(repositoryID: repository.id))
                }
            }
            await environment.windows.save(WindowSnapshot(id: UUID(), repositories: members))
        }
        return environment
    }
}
#endif
