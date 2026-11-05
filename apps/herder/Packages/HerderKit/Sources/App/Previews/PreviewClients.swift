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
    func repositoryKind(at url: URL) async throws -> GitRepositoryKind { .mainWorkingTree }
    func gitDirectory(of url: URL) async throws -> URL? { url.appending(path: ".git") }
    func status(in worktree: URL) async throws -> GitWorktreeStatus {
        let root = PathKey(worktree)
        return GitWorktreeStatus(root: root, entries: [root.appending("Package.swift"): .ignored])
    }
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
    /// An app environment over fakes, with two repositories already adopted.
    ///
    /// The store is in-memory and nothing queries it; the repositories go in
    /// through the state store, which is where they live now. Traps rather than
    /// returning an optional: a preview that cannot build its store has nothing
    /// to show, and the message is what tells you why the canvas is blank.
    @MainActor static var preview: AppEnvironment {
        let persistence: PersistenceStack
        do {
            persistence = try PersistenceStack.inMemory()
        } catch {
            fatalError("Could not build the preview store: \(error)")
        }

        let environment = AppEnvironment(
            files: PreviewFileClient(),
            bookmarks: PreviewBookmarkClient(),
            git: PreviewGitClient(),
            folderPicker: PreviewFolderPickerClient(),
            watcher: PreviewFileWatcherClient(),
            clock: LiveClockClient(),
            persistence: persistence
        )

        Task {
            for (index, name) in ["agent-editor", "herder"].enumerated() {
                let path = "/preview/\(name)"
                _ = try? await environment.repositories.add(url: URL(filePath: path), name: name)
                _ = index
            }
        }
        return environment
    }
}
#endif
