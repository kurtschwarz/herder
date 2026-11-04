#if DEBUG
import Clients
import Foundation
import Storage
import SwiftData

/// Does-nothing `FileClient` for SwiftUI previews. Debug-only so it never reaches a
/// release build; tests use `InMemoryFileClient` from `ClientsTestSupport` instead.
struct PreviewFileClient: FileClient {
    func read(_ path: String) async throws -> String { "" }
    func write(_ contents: String, to path: String) async throws {}
    func exists(_ path: String) async -> Bool { true }
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
    func worktrees(at url: URL) async throws -> [GitWorktree] {
        [
            GitWorktree(path: url, checkout: .branch("main"), isMainWorkingTree: true),
            GitWorktree(path: url.appending(path: "feature"), checkout: .branch("feature"), isMainWorkingTree: false),
        ]
    }
}

extension AppModel {
    /// Two workspaces in an in-memory store. One container for every preview,
    /// because a context outlives nothing: its container has to stay alive for
    /// as long as a view queries it. Traps rather than returning an optional: a
    /// preview that cannot build its store has nothing to show, and the message
    /// is what tells you why the canvas is blank.
    @MainActor static let previewContainer: ModelContainer = {
        do {
            let container = try WorkspaceContainer.inMemory()
            for (index, name) in ["agent-editor", "herder"].enumerated() {
                let path = "/preview/\(name)"
                container.mainContext.insert(
                    Workspace(name: name, path: path, bookmark: Data(path.utf8), order: index)
                )
            }
            return container
        } catch {
            fatalError("Could not build the preview workspace store: \(error)")
        }
    }()

    /// An app model over the seeded preview store.
    @MainActor static var preview: AppModel {
        AppModel(
            files: PreviewFileClient(),
            bookmarks: PreviewBookmarkClient(),
            git: PreviewGitClient(),
            folderPicker: PreviewFolderPickerClient(),
            context: previewContainer.mainContext
        )
    }
}
#endif
