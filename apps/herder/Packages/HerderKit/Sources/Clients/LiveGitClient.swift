import Foundation

/// `GitClient` that reads the repository layout off disk instead of running `git`.
///
/// The app is sandboxed, and a child process inherits that sandbox without
/// inheriting the security-scoped access the app holds, so shelling out to `git`
/// is unreliable exactly where it matters. Everything this client answers is
/// visible in the layout itself: `.git` as a directory means a main working tree,
/// `.git` as a file means a linked worktree and names its git directory, and a
/// repository directory with `bare = true` in its config is a bare repository.
public struct LiveGitClient: GitClient {
    public init() {}

    /// `@concurrent` because every step below is blocking disk I/O. Without it
    /// the whole walk would run on whichever actor called, which is the main one.
    @concurrent
    public func repositoryKind(at url: URL) async throws -> GitRepositoryKind {
        let url = url.resolvingSymlinksInPath()
        let dotGit = url.appending(path: ".git")

        switch entryKind(at: dotGit) {
        case .directory:
            return isGitDirectory(dotGit) ? .mainWorkingTree : .notARepository

        case .file:
            guard let gitDirectory = linkedGitDirectory(at: dotGit, relativeTo: url) else {
                return .notARepository
            }
            let common = commonDirectory(for: gitDirectory)
            return .linkedWorktree(mainRepository: repositoryRoot(forCommonDirectory: common))

        case .missing:
            // Either a bare repository, or not a repository at all. Picking the
            // `.git` directory of a working tree lands here too, and is refused:
            // the working tree beside it is the thing to add.
            return isGitDirectory(url) && isBare(url) ? .bare : .notARepository
        }
    }

    // MARK: - Layout

    private enum EntryKind {
        case directory, file, missing
    }

    private func entryKind(at url: URL) -> EntryKind {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        ) else {
            return .missing
        }
        return isDirectory.boolValue ? .directory : .file
    }

    /// A git directory always holds these, whether it is `.git` or a bare root.
    private func isGitDirectory(_ url: URL) -> Bool {
        ["HEAD", "objects", "refs"].allSatisfy {
            FileManager.default.fileExists(atPath: url.appending(path: $0).path(percentEncoded: false))
        }
    }

    /// `bare = true` under `[core]`. The section matters: a remote or a branch is
    /// free to have a key of the same name, and this is the only gate deciding
    /// whether a folder can become a workspace.
    private func isBare(_ url: URL) -> Bool {
        guard let config = try? String(contentsOf: url.appending(path: "config"), encoding: .utf8) else {
            return false
        }

        var inCore = false
        for line in config.split(separator: "\n") {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inCore = line.lowercased().hasPrefix("[core")
            } else if inCore, line.replacingOccurrences(of: " ", with: "").lowercased() == "bare=true" {
                return true
            }
        }
        return false
    }

    /// A linked worktree's `.git` is a file reading `gitdir: <path>`, where the
    /// path may be relative to the worktree.
    private func linkedGitDirectory(at file: URL, relativeTo root: URL) -> URL? {
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let prefix = "gitdir:"
        guard let line = contents.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        let path = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        return resolve(path, relativeTo: root)
    }

    /// The git directory shared by every worktree. `commondir` names it, relative
    /// to the worktree's own git directory; without it, that directory is
    /// `<common>/worktrees/<name>`.
    private func commonDirectory(for gitDirectory: URL) -> URL {
        let marker = gitDirectory.appending(path: "commondir")
        if let contents = try? String(contentsOf: marker, encoding: .utf8) {
            let path = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return resolve(path, relativeTo: gitDirectory)
            }
        }
        return gitDirectory.deletingLastPathComponent().deletingLastPathComponent()
    }

    /// The folder a user would call the repository: the working tree beside a
    /// `.git` directory, or the bare directory itself.
    private func repositoryRoot(forCommonDirectory common: URL) -> URL {
        common.lastPathComponent == ".git" ? common.deletingLastPathComponent() : common
    }

    private func resolve(_ path: String, relativeTo base: URL) -> URL {
        let url = path.hasPrefix("/")
            ? URL(filePath: path)
            : base.appending(path: path)
        return url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
