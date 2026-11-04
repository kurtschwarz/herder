import Foundation

/// Where a new worktree goes on disk.
///
/// Always inside the workspace folder: that is the folder the user handed the
/// app, so a worktree there is in reach of everything the workspace is.
public enum GitWorktreeLocation {
    /// Holds the worktrees of a repository that has a working tree of its own.
    /// Kept out of `git status` through the repository's exclude file.
    public static let containerName = ".worktrees"

    /// `nil` for anything but a main working tree or a bare repository.
    public static func path(
        forBranch branch: String,
        inRepository repository: URL,
        kind: GitRepositoryKind
    ) -> URL? {
        let folder = folderName(forBranch: branch)
        switch kind {
        case .mainWorkingTree:
            return repository.appending(path: containerName).appending(path: folder)
        case .bare:
            return repository.appending(path: folder)
        case .linkedWorktree, .notARepository:
            return nil
        }
    }

    /// A branch name can hold slashes, a folder name cannot.
    public static func folderName(forBranch branch: String) -> String {
        branch.replacingOccurrences(of: "/", with: "-")
    }
}
