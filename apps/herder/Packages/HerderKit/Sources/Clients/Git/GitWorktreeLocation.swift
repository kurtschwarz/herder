import Foundation

/// Where a new worktree goes on disk.
///
/// Always directly inside the workspace folder, whatever kind of repository it
/// is: a worktree there sits beside the repository's own files, and is in reach
/// of everything the workspace is.
public enum GitWorktreeLocation {
    /// `nil` for anything but a main working tree or a bare repository.
    public static func path(
        forBranch branch: String,
        inRepository repository: URL,
        kind: GitRepositoryKind
    ) -> URL? {
        switch kind {
        case .mainWorkingTree, .bare:
            return repository.appending(path: folderName(forBranch: branch))
        case .linkedWorktree, .notARepository:
            return nil
        }
    }

    /// A branch name can hold slashes, a folder name cannot.
    public static func folderName(forBranch branch: String) -> String {
        branch.replacingOccurrences(of: "/", with: "-")
    }
}
