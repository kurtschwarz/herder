import Foundation

/// `GitClient` that reads the repository layout off disk instead of running `git`.
///
/// Reading never shells out to `git`: it is quicker, needs no git install, and
/// everything these questions ask is visible in the layout itself. Only
/// `addWorktree`, which has to change the repository, runs the real thing.
/// The layout: `.git` as a directory means a main working tree,
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
            guard isGitDirectory(dotGit) else { return .notARepository }
            // A `.git` that is itself bare means the folder around it holds no
            // checkout: its worktrees are the folders beside `.git`.
            return isBare(dotGit) ? .bare : .mainWorkingTree

        case .file:
            guard let gitDirectory = linkedGitDirectory(at: dotGit, relativeTo: url) else {
                return .notARepository
            }
            // The file may name a bare repository rather than a worktree's own
            // git directory: the layout that hides the internals in `.bare` and
            // puts every checkout in a folder beside it. The folder holding the
            // two is the repository, and has no checkout of its own.
            if isGitDirectory(gitDirectory), isBare(gitDirectory) { return .bare }

            let common = commonDirectory(for: gitDirectory)
            return .linkedWorktree(mainRepository: repositoryRoot(forCommonDirectory: common))

        case .missing:
            // Either a bare repository, or not a repository at all. Picking the
            // `.git` directory of a working tree lands here too, and is refused:
            // the working tree beside it is the thing to add.
            return isGitDirectory(url) && isBare(url) ? .bare : .notARepository
        }
    }

    /// Main working tree first, then branches alphabetically, then detached
    /// checkouts. Linked worktrees whose folder has gone missing are skipped:
    /// git still lists them until pruned, but there is nothing to open.
    @concurrent
    public func worktrees(at url: URL) async throws -> [GitWorktree] {
        let url = url.resolvingSymlinksInPath()
        let dotGit = url.appending(path: ".git")

        var result: [GitWorktree] = []
        let gitDirectory: URL

        switch try await repositoryKind(at: url) {
        case .mainWorkingTree:
            gitDirectory = dotGit
            if let checkout = checkout(inGitDirectory: dotGit) {
                result.append(GitWorktree(
                    path: url,
                    checkout: checkout,
                    isMainWorkingTree: true,
                    lastActivity: lastActivity(inGitDirectory: dotGit)
                ))
            }
        case .bare:
            gitDirectory = bareGitDirectory(at: url)
        case .linkedWorktree, .notARepository:
            return []
        }

        let administrative = gitDirectory.appending(path: "worktrees")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: administrative.path(percentEncoded: false))) ?? []

        var linked: [GitWorktree] = []
        for name in names {
            let entry = administrative.appending(path: name)
            guard
                let pointer = try? String(contentsOf: entry.appending(path: "gitdir"), encoding: .utf8),
                let checkout = checkout(inGitDirectory: entry)
            else { continue }

            let marker = pointer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !marker.isEmpty else { continue }
            let path = resolve(marker, relativeTo: entry).deletingLastPathComponent()
            guard FileManager.default.fileExists(atPath: path.path(percentEncoded: false)) else { continue }

            linked.append(GitWorktree(
                path: path,
                checkout: checkout,
                isMainWorkingTree: false,
                lastActivity: lastActivity(inGitDirectory: entry)
            ))
        }

        linked.sort { lhs, rhs in
            switch (lhs.checkout, rhs.checkout) {
            case (.branch(let a), .branch(let b)):
                let order = a.localizedStandardCompare(b)
                return order == .orderedSame ? lhs.path.path < rhs.path.path : order == .orderedAscending
            case (.branch, .detached):
                return true
            case (.detached, .branch):
                return false
            case (.detached, .detached):
                return lhs.path.path < rhs.path.path
            }
        }
        return result + linked
    }

    /// Every local branch, loose and packed, sorted.
    @concurrent
    public func branches(at url: URL) async throws -> [String] {
        let url = url.resolvingSymlinksInPath()

        let gitDirectory: URL
        switch try await repositoryKind(at: url) {
        case .mainWorkingTree: gitDirectory = url.appending(path: ".git")
        case .bare: gitDirectory = bareGitDirectory(at: url)
        case .linkedWorktree, .notARepository: return []
        }

        var names = Set<String>()
        let heads = gitDirectory.appending(path: "refs/heads").path(percentEncoded: false)
        for relative in (try? FileManager.default.subpathsOfDirectory(atPath: heads)) ?? [] {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: heads + "/" + relative, isDirectory: &isDirectory)
            if exists, !isDirectory.boolValue { names.insert(relative) }
        }

        if let packed = try? String(contentsOf: gitDirectory.appending(path: "packed-refs"), encoding: .utf8) {
            let prefix = "refs/heads/"
            for line in packed.split(separator: "\n") where !line.hasPrefix("#") && !line.hasPrefix("^") {
                let parts = line.split(separator: " ", maxSplits: 1)
                if parts.count == 2, parts[1].hasPrefix(prefix) {
                    names.insert(String(parts[1].dropFirst(prefix.count)))
                }
            }
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    @concurrent
    public func addWorktree(
        in repository: URL,
        at path: URL,
        newBranch: String,
        from base: String
    ) async throws {
        // Before resolving: `path` was built from `repository` as the caller
        // had it, so that is the pair that compares.
        let excluded = GitWorktreeLocation.topLevelFolder(of: path, inRepository: repository)
        let repository = repository.resolvingSymlinksInPath()
        if let excluded { exclude(excluded, inRepository: repository) }

        try runGit([
            "-C", repository.path(percentEncoded: false),
            "worktree", "add",
            "-b", newBranch,
            path.path(percentEncoded: false),
            base,
        ])
    }

    // MARK: - Running git

    private func runGit(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = arguments
        // A credential prompt has nowhere to appear and would hang the call.
        process.environment = ProcessInfo.processInfo.environment
            .merging(["GIT_TERMINAL_PROMPT": "0"]) { _, new in new }

        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        let output = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: output, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitClientError.commandFailed(message.isEmpty ? "git exited with \(process.terminationStatus)" : message)
        }
    }

    /// Keeps a worktree inside a working tree out of `git status`, where it
    /// would otherwise show as untracked. Goes in the repository's own exclude
    /// file so no tracked file changes. A repository with no checkout of its
    /// own has no status to keep clean. Best effort: a failure here only means
    /// the folder shows up as untracked.
    private func exclude(_ folder: String, inRepository repository: URL) {
        let dotGit = repository.appending(path: ".git")
        guard entryKind(at: dotGit) == .directory, !isBare(dotGit) else { return }

        let info = dotGit.appending(path: "info")
        let exclude = info.appending(path: "exclude")
        // Anchored, so only this folder at the top is ignored, not any folder
        // of the same name deeper down.
        let entry = "/\(folder)/"

        let existing = (try? String(contentsOf: exclude, encoding: .utf8)) ?? ""
        guard !existing.split(separator: "\n").contains(where: { $0 == entry }) else { return }

        try? FileManager.default.createDirectory(at: info, withIntermediateDirectories: true)
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        try? (existing + separator + entry + "\n").write(to: exclude, atomically: true, encoding: .utf8)
    }

    /// The reflog's modification time: git appends to it on every commit and
    /// checkout, so it tracks the working tree better than `HEAD` itself, which
    /// only changes on a checkout.
    private func lastActivity(inGitDirectory directory: URL) -> Date? {
        for name in ["logs/HEAD", "HEAD"] {
            let path = directory.appending(path: name).path(percentEncoded: false)
            if let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date {
                return date
            }
        }
        return nil
    }

    // MARK: - Layout

    /// What a git directory's `HEAD` points at: `ref: refs/heads/<branch>` on a
    /// branch, a bare commit id when detached.
    private func checkout(inGitDirectory directory: URL) -> GitWorktree.Checkout? {
        guard
            let head = try? String(contentsOf: directory.appending(path: "HEAD"), encoding: .utf8)
        else { return nil }
        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)

        let prefix = "ref:"
        if line.hasPrefix(prefix) {
            let ref = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            let heads = "refs/heads/"
            return .branch(ref.hasPrefix(heads) ? String(ref.dropFirst(heads.count)) : ref)
        }
        return line.isEmpty ? nil : .detached(sha: String(line.prefix(7)))
    }

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

    /// Where a bare repository keeps its git files: the folder itself, or the
    /// `.git` inside a project folder that has no checkout of its own.
    private func bareGitDirectory(at url: URL) -> URL {
        if isGitDirectory(url) { return url }
        let dotGit = url.appending(path: ".git")
        guard entryKind(at: dotGit) == .file else { return dotGit }
        return linkedGitDirectory(at: dotGit, relativeTo: url) ?? dotGit
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
        let parent = common.deletingLastPathComponent()
        if common.lastPathComponent == ".git" { return parent }

        // A `.git` file beside the git directory, naming it, means the folder
        // holding both is what the user calls the repository. That is the
        // `.bare` layout, where the git directory is not named `.git` at all.
        let dotGit = parent.appending(path: ".git")
        if entryKind(at: dotGit) == .file,
           let named = linkedGitDirectory(at: dotGit, relativeTo: parent),
           isSameFolder(named, common) {
            return parent
        }
        return common
    }

    /// Compares two folder URLs by path. Resolving one of them can leave a
    /// trailing slash the other does not have, which is enough to make two URLs
    /// for the same folder unequal.
    private func isSameFolder(_ lhs: URL, _ rhs: URL) -> Bool {
        func key(_ url: URL) -> String {
            let path = url.path(percentEncoded: false)
            return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        }
        return key(lhs) == key(rhs)
    }

    private func resolve(_ path: String, relativeTo base: URL) -> URL {
        let url = path.hasPrefix("/")
            ? URL(filePath: path)
            : base.appending(path: path)
        return url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
