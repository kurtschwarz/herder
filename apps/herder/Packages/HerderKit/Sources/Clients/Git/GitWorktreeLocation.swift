import Foundation

/// Where a new worktree goes on disk.
///
/// Always inside the workspace folder, whatever kind of repository it is: a
/// worktree there sits beside the repository's own files, and is in reach of
/// everything the workspace is.
public enum GitWorktreeLocation {
    /// The branch name is the path, slashes and all, so `agent/add-minimap`
    /// lands in an `agent` folder. That is what `git worktree add <branch>`
    /// does, and it keeps a family of branches together instead of spreading
    /// flattened names across the root.
    ///
    /// `nil` for anything but a main working tree or a bare repository.
    public static func path(
        forBranch branch: String,
        inRepository repository: URL,
        kind: GitRepositoryKind
    ) -> URL? {
        switch kind {
        case .mainWorkingTree, .bare:
            return repository.appending(path: branch)
        case .linkedWorktree, .notARepository:
            return nil
        }
    }

    /// The folder directly inside `repository` that holds `path`, which for a
    /// nested worktree is the first part of its branch name. `nil` when `path`
    /// is not inside `repository` at all.
    ///
    /// Compares the two as given: a caller builds one from the other, so
    /// resolving either here could only make them stop matching.
    public static func topLevelFolder(of path: URL, inRepository repository: URL) -> String? {
        let root = repository.standardizedFileURL.path(percentEncoded: false)
        let prefix = root.hasSuffix("/") ? root : root + "/"
        let full = path.standardizedFileURL.path(percentEncoded: false)

        guard full.hasPrefix(prefix) else { return nil }
        return full.dropFirst(prefix.count).split(separator: "/").first.map(String.init)
    }
}
