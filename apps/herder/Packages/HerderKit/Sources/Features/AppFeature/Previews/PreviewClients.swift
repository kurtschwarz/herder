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

struct PreviewGitClient: GitClient {
    func repositoryKind(at url: URL) async throws -> GitRepositoryKind { .mainWorkingTree }
    func worktrees(at url: URL) async throws -> [GitWorktree] { [] }
}

extension AppModel {
    /// An app model backed by an empty in-memory store. Traps rather than
    /// returning an optional: a preview that cannot build its store has nothing
    /// to show, and the message is what tells you why the canvas is blank.
    static var preview: AppModel {
        do {
            return AppModel(
                files: PreviewFileClient(),
                bookmarks: PreviewBookmarkClient(),
                git: PreviewGitClient(),
                context: ModelContext(try WorkspaceContainer.inMemory())
            )
        } catch {
            fatalError("Could not build the preview workspace store: \(error)")
        }
    }
}
#endif
