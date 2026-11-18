import Core
import Foundation
import Services
import TestSupport
import Testing

/// Builds real repositories on disk with real `git`, so the expected answers come
/// from git itself rather than from the same layout rules the client applies.
/// Tests are not sandboxed, so running `git` here is safe; the client under test
/// deliberately does not.
@Suite struct LiveGitClientTests {
    let directory: URL
    let client = LiveGitClient()

    init() throws {
        directory = URL.temporaryDirectory
            .appending(path: "LiveGitClientTests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @discardableResult
    func git(_ arguments: String..., in url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = url
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            Issue.record("git \(arguments.joined(separator: " ")) failed: \(output)")
            throw CocoaError(.fileNoSuchFile)
        }
        return output
    }

    func makeDirectory(_ name: String) throws -> URL {
        let url = directory.appending(path: name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Who commits, and that they do not sign.
    ///
    /// The developer's own git config may sign commits, and a signing agent
    /// asked for dozens of signatures by a parallel test run starts refusing —
    /// which showed up as six tests failing with "1Password: agent returned an
    /// error" and nothing wrong with the code. Nothing here tests signatures.
    ///
    /// One helper rather than three lines repeated at each site, because the
    /// site that forgets the third line is the site that fails on someone
    /// else's machine. That is how this was missed the first time: the working
    /// copies opted out and the six bare-repository seeds did not.
    func configureIdentity(in url: URL) throws {
        try git("config", "user.email", "test@example.com", in: url)
        try git("config", "user.name", "Test", in: url)
        try git("config", "commit.gpgsign", "false", in: url)
    }

    /// Writes a file and commits it, so a repository has something to branch
    /// from. `git worktree add` needs a commit to exist.
    func commitSomething(in url: URL) throws {
        try Data("x".utf8).write(to: url.appending(path: "README.md"))
        try git("add", ".", in: url)
        try git("commit", "-m", "first", in: url)
    }

    /// A repository with one commit, so `git worktree add` has something to branch.
    func makeRepository(_ name: String) throws -> URL {
        let url = try makeDirectory(name)
        try git("init", "--initial-branch=main", in: url)
        try configureIdentity(in: url)
        try commitSomething(in: url)
        return url
    }

    /// Relative paths and their status, which is what the assertions read more
    /// clearly than a dictionary keyed on absolute URLs.
    func statuses(_ status: GitWorktreeStatus) -> [String: GitStatus] {
        Dictionary(uniqueKeysWithValues: status.entries.map {
            (String($0.key.path.dropFirst(status.root.path.count + 1)), $0.value)
        })
    }

    @Test func contentsAreTheCommittedTextNotTheWorkingOrStagedOne() async throws {
        let repo = try makeRepository("committed")
        try FileManager.default.createDirectory(at: repo.appending(path: "sub"), withIntermediateDirectories: true)
        try Data("committed\n".utf8).write(to: repo.appending(path: "sub/file.txt"))
        try git("add", ".", in: repo)
        try git("commit", "-m", "second", in: repo)
        try Data("staged\n".utf8).write(to: repo.appending(path: "sub/file.txt"))
        try git("add", ".", in: repo)
        try Data("working\n".utf8).write(to: repo.appending(path: "sub/file.txt"))

        let text = try await client.contents(of: repo.appending(path: "sub/file.txt"), atRevision: "HEAD", in: repo)

        #expect(text == "committed\n")
    }

    @Test func contentsAreNilForAFileNotInTheRevision() async throws {
        let repo = try makeRepository("not-committed")
        try Data("new\n".utf8).write(to: repo.appending(path: "new.txt"))
        try git("add", "new.txt", in: repo)

        #expect(try await client.contents(of: repo.appending(path: "new.txt"), atRevision: "HEAD", in: repo) == nil)
        #expect(try await client.contents(of: repo.appending(path: "nope.txt"), atRevision: "HEAD", in: repo) == nil)
    }

    @Test func contentsAreNilForAFileThatIsNotUTF8() async throws {
        let repo = try makeRepository("binary")
        try Data([0xFF, 0xFE, 0x00, 0x80]).write(to: repo.appending(path: "blob.bin"))
        try git("add", ".", in: repo)
        try git("commit", "-m", "binary", in: repo)

        #expect(try await client.contents(of: repo.appending(path: "blob.bin"), atRevision: "HEAD", in: repo) == nil)
    }

    @Test func contentsAreNilOutsideARepository() async throws {
        let plain = try makeDirectory("plain-contents")
        try Data("x".utf8).write(to: plain.appending(path: "a.txt"))

        #expect(try await client.contents(of: plain.appending(path: "a.txt"), atRevision: "HEAD", in: plain) == nil)
    }

    @Test func changeSummaryCountsCommittedAndUncommittedLinesAgainstTheMergeBase() async throws {
        let repo = try makeRepository("changes")
        try git("checkout", "-b", "feature", in: repo)
        try Data("x\na\nb\n".utf8).write(to: repo.appending(path: "README.md"))
        try git("commit", "-am", "more", in: repo)
        // Main moves on after the fork, which the merge-base ignores.
        try git("checkout", "main", in: repo)
        try Data("x\nmain only\n".utf8).write(to: repo.appending(path: "other.txt"))
        try git("add", ".", in: repo)
        try git("commit", "-m", "main moves", in: repo)
        try git("checkout", "feature", in: repo)
        // Staged and unstaged, both tracked.
        try Data("a\nb\nc\nd\n".utf8).write(to: repo.appending(path: "README.md"))
        try Data("new\n".utf8).write(to: repo.appending(path: "added.txt"))
        try git("add", "added.txt", in: repo)
        // Untracked: not counted.
        try Data("ignored\nby\nthe\ncount\n".utf8).write(to: repo.appending(path: "untracked.txt"))

        let summary = try await client.changeSummary(in: repo)

        // README: x -> a b c d is 4 inserted, 1 deleted; added.txt: 1 inserted.
        #expect(summary == GitChangeSummary(insertions: 5, deletions: 1))
    }

    @Test func changeSummaryFallsBackToMaster() async throws {
        let repo = try makeDirectory("master-repo")
        try git("init", "--initial-branch=master", in: repo)
        try configureIdentity(in: repo)
        try commitSomething(in: repo)
        try Data("x\ny\n".utf8).write(to: repo.appending(path: "README.md"))

        #expect(try await client.changeSummary(in: repo) == GitChangeSummary(insertions: 2, deletions: 1))
    }

    @Test func changeSummaryIsNilWithoutADefaultBranch() async throws {
        let repo = try makeDirectory("trunk-repo")
        try git("init", "--initial-branch=trunk", in: repo)
        try configureIdentity(in: repo)
        try commitSomething(in: repo)

        #expect(try await client.changeSummary(in: repo) == nil)
    }

    @Test func changeSummaryIsNilOutsideAWorktree() async throws {
        let plain = try makeDirectory("plain-changes")
        #expect(try await client.changeSummary(in: plain) == nil)
    }

    @Test func mergeBaseOfAnAncestorIsTheAncestorAndOfNothingIsNil() async throws {
        let repo = try makeRepository("merge-base")
        try Data("x\na\n".utf8).write(to: repo.appending(path: "README.md"))
        try git("commit", "-am", "second", in: repo)
        let first = try git("rev-parse", "HEAD~1", in: repo).trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(try await client.mergeBase(of: "HEAD~1", in: repo) == first)
        #expect(try await client.mergeBase(of: "nope", in: repo) == nil)
        #expect(try await client.mergeBase(of: "--output=x", in: repo) == nil)
    }

    @Test func changedFilesListTrackedChangesWithCountsAndLeaveUntrackedOut() async throws {
        let repo = try makeRepository("changed-files")
        try Data("a\nb\nc\n".utf8).write(to: repo.appending(path: "README.md"))
        try Data("new\n".utf8).write(to: repo.appending(path: "added.txt"))
        try git("add", "added.txt", in: repo)
        try Data("loose\n".utf8).write(to: repo.appending(path: "untracked.txt"))

        let files = try await client.changedFiles(since: "HEAD", in: repo)

        #expect(files.map(\.path) == ["added.txt", "README.md"])
        #expect(files.map(\.status) == [.added, .modified])
        #expect(files[0].insertions == 1)
    }

    @Test func refsAndCommitsAreListedAndAShaAbbreviationResolves() async throws {
        let repo = try makeRepository("refs")
        try git("tag", "v1", in: repo)
        try git("branch", "other", in: repo)
        let sha = try git("rev-parse", "HEAD", in: repo).trimmingCharacters(in: .whitespacesAndNewlines)

        let refs = try await client.refs(in: repo)
        #expect(Set(refs.map(\.name)) == ["main", "other", "v1"])
        #expect(try await client.recentCommits(limit: 5, in: repo).map(\.sha) == [sha])
        #expect(try await client.commit(matching: String(sha.prefix(7)), in: repo)?.sha == sha)
        #expect(try await client.commit(matching: "feedbeef", in: repo) == nil)
    }

    @Test func statusFindsWhatGitIgnoresIncludingNestedRulesAndNegations() async throws {
        let repo = try makeRepository("repo")
        try Data("*.log\nbuild/\n!keep.log\n".utf8).write(to: repo.appending(path: ".gitignore"))
        try FileManager.default.createDirectory(at: repo.appending(path: "build"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: repo.appending(path: "build/out.o"))
        try FileManager.default.createDirectory(at: repo.appending(path: "sub"), withIntermediateDirectories: true)
        try Data("*.tmp\n".utf8).write(to: repo.appending(path: "sub/.gitignore"))
        for name in ["debug.log", "keep.log"] {
            try Data("x".utf8).write(to: repo.appending(path: name))
        }
        for name in ["x.tmp", "y.txt"] {
            try Data("x".utf8).write(to: repo.appending(path: "sub/\(name)"))
        }

        let found = statuses(try await client.status(in: repo))

        #expect(found["debug.log"] == .ignored)
        // A nested ignore file counts, and is reported even though the folder
        // holding it collapsed as untracked.
        #expect(found["sub"] == .untracked)
        #expect(found["sub/x.tmp"] == .ignored)
        // Negated back in, so untracked rather than ignored.
        #expect(found["keep.log"] == .untracked)
    }

    /// The flag that keeps the output small: an ignored or untracked folder is
    /// one entry, and nothing inside it is walked or reported.
    @Test func statusCollapsesIgnoredAndUntrackedFolders() async throws {
        let repo = try makeRepository("collapsing")
        try Data("build/\n".utf8).write(to: repo.appending(path: ".gitignore"))
        for name in ["build", "fresh"] {
            try FileManager.default.createDirectory(at: repo.appending(path: name), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: repo.appending(path: "\(name)/inside.txt"))
        }

        let found = statuses(try await client.status(in: repo))

        #expect(found["build"] == .ignored)
        #expect(found["fresh"] == .untracked)
        #expect(found["build/inside.txt"] == nil)
        #expect(found["fresh/inside.txt"] == nil)
    }

    @Test func statusKeepsStagedAndUnstagedApart() async throws {
        let repo = try makeRepository("columns")
        try Data("one".utf8).write(to: repo.appending(path: "staged.txt"))
        try git("add", "staged.txt", in: repo)
        try Data("two".utf8).write(to: repo.appending(path: "staged.txt"))
        try Data("edited".utf8).write(to: repo.appending(path: "README.md"))

        let found = statuses(try await client.status(in: repo))

        #expect(found["staged.txt"] == .tracked(staged: .added, unstaged: .modified))
        #expect(found["README.md"] == .tracked(staged: .unchanged, unstaged: .modified))
    }

    @Test func statusReportsADeletedFile() async throws {
        let repo = try makeRepository("gone")

        try git("rm", "--quiet", "README.md", in: repo)

        // Nothing is left on disk, so no row will draw it: the entry is here
        // only so the folder it was in can say something went missing.
        #expect(statuses(try await client.status(in: repo))["README.md"]
            == .tracked(staged: .deleted, unstaged: .unchanged))
    }

    @Test func statusReportsWhereARenameCameFrom() async throws {
        let repo = try makeRepository("renamed")
        // Content git cannot confuse with README.md's, or rename detection is
        // free to pair the two files the other way round.
        try Data("something else entirely".utf8).write(to: repo.appending(path: "moved.txt"))
        try git("add", ".", in: repo)
        try git("commit", "-m", "second", in: repo)
        try git("mv", "moved.txt", "elsewhere.txt", in: repo)

        let found = statuses(try await client.status(in: repo))

        #expect(found["elsewhere.txt"] == .tracked(staged: .renamed, unstaged: .unchanged))
        #expect(found["moved.txt"] == .tracked(staged: .renamed, unstaged: .unchanged))
    }

    @Test func statusReadsAPathWithSpacesAndQuotesInIt() async throws {
        let repo = try makeRepository("awkward")
        let name = #"a "quoted" name.txt"#
        try Data("x".utf8).write(to: repo.appending(path: name))

        #expect(statuses(try await client.status(in: repo))[name] == .untracked)
    }

    @Test func statusIsEmptyOutsideARepository() async throws {
        let plain = try makeDirectory("plain-status")
        try Data("x".utf8).write(to: plain.appending(path: "a.log"))

        #expect(try await client.status(in: plain).entries.isEmpty)
    }

    @Test func plainFolderIsNotARepository() async throws {
        let url = try makeDirectory("plain")
        #expect(try await client.repositoryKind(at: url) == .notARepository)
    }

    @Test func repositoryRootIsAMainWorkingTree() async throws {
        let url = try makeRepository("repo")
        #expect(try await client.repositoryKind(at: url) == .mainWorkingTree)
    }

    @Test func subdirectoryOfARepositoryIsNotARepository() async throws {
        let repository = try makeRepository("repo")
        let nested = repository.appending(path: "src")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        #expect(try await client.repositoryKind(at: nested) == .notARepository)
    }

    @Test func bareRepositoryIsRecognised() async throws {
        let url = try makeDirectory("api.git")
        try git("init", "--bare", in: url)
        #expect(try await client.repositoryKind(at: url) == .bare)
    }

    @Test func linkedWorktreeReportsItsMainRepository() async throws {
        let repository = try makeRepository("repo")
        let worktree = directory.appending(path: "feature")
        try git("worktree", "add", worktree.path(percentEncoded: false), "-b", "feature", in: repository)

        let kind = try await client.repositoryKind(at: worktree)
        #expect(kind == .linkedWorktree(mainRepository: repository.resolvingSymlinksInPath()))
    }

    @Test func worktreeOfABareRepositoryReportsTheBareDirectory() async throws {
        let bare = try makeDirectory("origin.git")
        try git("init", "--bare", "--initial-branch=main", in: bare)

        // A bare repo has no commits yet, so seed one through a temporary clone.
        let seed = try makeDirectory("seed")
        try git("clone", bare.path(percentEncoded: false), seed.path(percentEncoded: false), in: directory)
        try configureIdentity(in: seed)
        try commitSomething(in: seed)
        try git("push", "origin", "main", in: seed)

        let worktree = directory.appending(path: "bare-feature")
        try git("worktree", "add", worktree.path(percentEncoded: false), "main", in: bare)

        let kind = try await client.repositoryKind(at: worktree)
        #expect(kind == .linkedWorktree(mainRepository: bare.resolvingSymlinksInPath()))
    }

    // MARK: - A project folder whose .git is bare

    /// The layout with no checkout at the root: `.git` is a bare repository and
    /// every worktree is a folder beside it.
    func makeProjectWithBareDotGit(_ name: String) throws -> URL {
        let project = try makeDirectory(name)
        let dotGit = project.appending(path: ".git")
        try FileManager.default.createDirectory(at: dotGit, withIntermediateDirectories: true)
        try git("init", "--bare", "--initial-branch=main", in: dotGit)

        let seed = try makeDirectory("seed-\(name)")
        try git("clone", dotGit.path(percentEncoded: false), seed.path(percentEncoded: false), in: directory)
        try configureIdentity(in: seed)
        try commitSomething(in: seed)
        try git("push", "origin", "main", in: seed)

        try git("worktree", "add", "main", "main", in: project)
        return project
    }

    @Test func aProjectWhoseDotGitIsBareIsABareRepository() async throws {
        let project = try makeProjectWithBareDotGit("project")
        #expect(try await client.repositoryKind(at: project) == .bare)
    }

    @Test func itsWorktreesAreTheFoldersBesideDotGitAndNotTheRoot() async throws {
        let project = try makeProjectWithBareDotGit("project")

        let trees = try await client.worktrees(at: project)

        #expect(trees.map(\.checkout) == [.branch("main")])
        #expect(trees.first?.path == project.appending(path: "main").resolvingSymlinksInPath())
        #expect(trees.first?.isMainWorkingTree == false)
    }

    @Test func itListsItsBranches() async throws {
        let project = try makeProjectWithBareDotGit("project")
        #expect(try await client.branches(at: project) == ["main"])
    }

    @Test func aWorktreeOfItNamesTheProjectFolderAsItsRepository() async throws {
        let project = try makeProjectWithBareDotGit("project")
        let kind = try await client.repositoryKind(at: project.appending(path: "main"))
        #expect(kind == .linkedWorktree(mainRepository: project.resolvingSymlinksInPath()))
    }

    @Test func addingToItCreatesASiblingAndLeavesTheExcludeFileAlone() async throws {
        let project = try makeProjectWithBareDotGit("project")
        let path = GitWorktreeLocation.path(forBranch: "feature", inRepository: project, kind: .bare)!

        try await client.addWorktree(in: project, at: path, newBranch: "feature", from: "main")

        let trees = try await client.worktrees(at: project)
        #expect(trees.map(\.checkout) == [.branch("feature"), .branch("main")])
        #expect(path.deletingLastPathComponent().standardizedFileURL == project.standardizedFileURL)
        let exclude = try? String(contentsOf: project.appending(path: ".git/info/exclude"), encoding: .utf8)
        #expect(exclude?.contains("/feature/") != true)
    }

    // MARK: - A project folder with a .bare and a .git file

    /// The layout the `.bare` convention produces: the git internals hidden in
    /// `.bare`, a one-line `.git` file naming it, and every checkout a folder
    /// beside them.
    func makeBareLayout(_ name: String) throws -> URL {
        let project = try makeDirectory(name)
        let bare = project.appending(path: ".bare")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        try git("init", "--bare", "--initial-branch=main", in: bare)
        try Data("gitdir: ./.bare\n".utf8).write(to: project.appending(path: ".git"))

        let seed = try makeDirectory("seed-\(name)")
        try git("clone", bare.path(percentEncoded: false), seed.path(percentEncoded: false), in: directory)
        try configureIdentity(in: seed)
        try commitSomething(in: seed)
        try git("push", "origin", "main", in: seed)

        try git("worktree", "add", "main", "main", in: project)
        return project
    }

    @Test func aDotGitFileNamingABareRepositoryIsABareRepository() async throws {
        let project = try makeBareLayout("project")
        #expect(try await client.repositoryKind(at: project) == .bare)
    }

    @Test func itsWorktreesAreTheFoldersBesideTheBareDirectory() async throws {
        let project = try makeBareLayout("project")

        let trees = try await client.worktrees(at: project)

        #expect(trees.map(\.checkout) == [.branch("main")])
        #expect(trees.first?.path == project.appending(path: "main").resolvingSymlinksInPath())
        #expect(trees.first?.isMainWorkingTree == false)
    }

    @Test func itListsItsBranchesFromTheBareDirectory() async throws {
        let project = try makeBareLayout("project")
        #expect(try await client.branches(at: project) == ["main"])
    }

    @Test func oneOfItsWorktreesPointsBackAtTheProjectFolder() async throws {
        let project = try makeBareLayout("project")

        let kind = try await client.repositoryKind(at: project.appending(path: "main"))

        // Not `.bare`, which is where the files are, and not the worktree itself.
        #expect(kind == .linkedWorktree(mainRepository: project.resolvingSymlinksInPath()))
    }

    @Test func addingToItCreatesAFolderBesideTheOthers() async throws {
        let project = try makeBareLayout("project")
        let path = GitWorktreeLocation.path(forBranch: "feature", inRepository: project, kind: .bare)!

        try await client.addWorktree(in: project, at: path, newBranch: "feature", from: "main")

        let trees = try await client.worktrees(at: project)
        #expect(trees.map(\.checkout) == [.branch("feature"), .branch("main")])
        #expect(path.deletingLastPathComponent().standardizedFileURL == project.standardizedFileURL)
    }

    @Test func missingFolderIsNotARepository() async throws {
        let url = directory.appending(path: "nothing-here")
        #expect(try await client.repositoryKind(at: url) == .notARepository)
    }

    // MARK: - worktrees

    @Test func repositoryWithoutWorktreesListsOnlyItsMainWorkingTree() async throws {
        let repository = try makeRepository("repo")
        let trees = try await client.worktrees(at: repository)
        #expect(trees.count == 1)
        #expect(trees.first?.path == repository.resolvingSymlinksInPath())
        #expect(trees.first?.checkout == .branch("main"))
        #expect(trees.first?.isMainWorkingTree == true)
    }

    @Test func worktreesReportWhenTheyLastChanged() async throws {
        let repository = try makeRepository("repo")
        let linked = directory.appending(path: "feature")
        try git("worktree", "add", linked.path(percentEncoded: false), "-b", "feature", in: repository)

        let trees = try await client.worktrees(at: repository)

        for tree in trees {
            let activity = try #require(tree.lastActivity)
            #expect(abs(activity.timeIntervalSinceNow) < 120)
        }
    }

    // MARK: - branches

    @Test func listsLocalBranchesIncludingSlashedAndPackedOnes() async throws {
        let repository = try makeRepository("repo")
        try git("branch", "agent/add-minimap", in: repository)
        try git("branch", "zeta", in: repository)
        try git("pack-refs", "--all", in: repository)
        try git("branch", "alpha", in: repository)

        let branches = try await client.branches(at: repository)

        #expect(branches == ["agent/add-minimap", "alpha", "main", "zeta"])
    }

    @Test func aBareRepositoryListsItsBranches() async throws {
        let bare = try makeDirectory("origin.git")
        try git("init", "--bare", "--initial-branch=main", in: bare)
        let seed = try makeDirectory("seed")
        try git("clone", bare.path(percentEncoded: false), seed.path(percentEncoded: false), in: directory)
        try configureIdentity(in: seed)
        try commitSomething(in: seed)
        try git("push", "origin", "main", in: seed)

        #expect(try await client.branches(at: bare) == ["main"])
    }

    @Test func nonRepositoriesAndLinkedWorktreesHaveNoBranchList() async throws {
        #expect(try await client.branches(at: try makeDirectory("plain")).isEmpty)

        let repository = try makeRepository("repo")
        let linked = directory.appending(path: "linked")
        try git("worktree", "add", linked.path(percentEncoded: false), "-b", "linked", in: repository)
        #expect(try await client.branches(at: linked).isEmpty)
    }

    // MARK: - addWorktree

    @Test func addingAWorktreeCreatesItOnANewBranch() async throws {
        let repository = try makeRepository("repo")
        let path = GitWorktreeLocation.path(
            forBranch: "agent/add-minimap",
            inRepository: repository,
            kind: .mainWorkingTree
        )!

        try await client.addWorktree(in: repository, at: path, newBranch: "agent/add-minimap", from: "main")

        let trees = try await client.worktrees(at: repository)
        #expect(trees.map(\.checkout) == [.branch("main"), .branch("agent/add-minimap")])
        #expect(trees.last?.path == path.resolvingSymlinksInPath())
        #expect(path.pathComponents.suffix(2) == ["agent", "add-minimap"])
    }

    @Test func aNestedWorktreeExcludesTheFolderItSitsIn() async throws {
        let repository = try makeRepository("repo")
        let path = GitWorktreeLocation.path(
            forBranch: "agent/add-minimap",
            inRepository: repository,
            kind: .mainWorkingTree
        )!

        try await client.addWorktree(in: repository, at: path, newBranch: "agent/add-minimap", from: "main")

        #expect(try git("status", "--porcelain", in: repository).isEmpty)
        let exclude = try String(contentsOf: repository.appending(path: ".git/info/exclude"), encoding: .utf8)
        // The folder git made for the branch family, not the worktree itself.
        #expect(exclude.split(separator: "\n").contains("/agent/"))
    }

    @Test func theWorktreeFolderStaysOutOfGitStatus() async throws {
        let repository = try makeRepository("repo")
        let path = GitWorktreeLocation.path(forBranch: "feature", inRepository: repository, kind: .mainWorkingTree)!

        try await client.addWorktree(in: repository, at: path, newBranch: "feature", from: "main")
        try await client.addWorktree(
            in: repository,
            at: GitWorktreeLocation.path(forBranch: "other", inRepository: repository, kind: .mainWorkingTree)!,
            newBranch: "other",
            from: "main"
        )

        #expect(try git("status", "--porcelain", in: repository).isEmpty)
        let exclude = try String(contentsOf: repository.appending(path: ".git/info/exclude"), encoding: .utf8)
        #expect(exclude.split(separator: "\n").filter { $0 == "/feature/" || $0 == "/other/" }.count == 2)
    }

    @Test func addingToABareRepositoryPutsTheWorktreeBesideTheRest() async throws {
        let bare = try makeDirectory("origin.git")
        try git("init", "--bare", "--initial-branch=main", in: bare)
        let seed = try makeDirectory("seed")
        try git("clone", bare.path(percentEncoded: false), seed.path(percentEncoded: false), in: directory)
        try configureIdentity(in: seed)
        try commitSomething(in: seed)
        try git("push", "origin", "main", in: seed)

        let path = GitWorktreeLocation.path(forBranch: "feature", inRepository: bare, kind: .bare)!
        try await client.addWorktree(in: bare, at: path, newBranch: "feature", from: "main")

        let trees = try await client.worktrees(at: bare)
        #expect(trees.map(\.checkout) == [.branch("feature")])
        #expect(path.deletingLastPathComponent().standardizedFileURL == bare.standardizedFileURL)
    }

    @Test func gitsRefusalComesBackAsTheError() async throws {
        let repository = try makeRepository("repo")
        let path = GitWorktreeLocation.path(forBranch: "main", inRepository: repository, kind: .mainWorkingTree)!

        let error = await #expect(throws: GitClientError.self) {
            try await client.addWorktree(in: repository, at: path, newBranch: "main", from: "main")
        }

        guard case .commandFailed(let message)? = error else {
            Issue.record("expected commandFailed")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test func linkedWorktreesFollowMainAndSortByBranch() async throws {
        let repository = try makeRepository("repo")
        for branch in ["zeta", "alpha"] {
            let path = directory.appending(path: branch)
            try git("worktree", "add", path.path(percentEncoded: false), "-b", branch, in: repository)
        }

        let trees = try await client.worktrees(at: repository)
        #expect(trees.map(\.checkout) == [.branch("main"), .branch("alpha"), .branch("zeta")])
        #expect(trees.map(\.isMainWorkingTree) == [true, false, false])
        #expect(trees[1].path == directory.appending(path: "alpha").resolvingSymlinksInPath())
    }

    @Test func detachedWorktreeShowsShortShaAndSortsLast() async throws {
        let repository = try makeRepository("repo")
        let detached = directory.appending(path: "detached")
        try git("worktree", "add", "--detach", detached.path(percentEncoded: false), in: repository)
        let branch = directory.appending(path: "beta")
        try git("worktree", "add", branch.path(percentEncoded: false), "-b", "beta", in: repository)

        let sha = try git("rev-parse", "--short=7", "HEAD", in: repository)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trees = try await client.worktrees(at: repository)
        #expect(trees.map(\.checkout) == [.branch("main"), .branch("beta"), .detached(sha: sha)])
    }

    @Test func bareRepositoryContributesOnlyItsWorktrees() async throws {
        let bare = try makeDirectory("origin.git")
        try git("init", "--bare", "--initial-branch=main", in: bare)
        let seed = try makeDirectory("seed")
        try git("clone", bare.path(percentEncoded: false), seed.path(percentEncoded: false), in: directory)
        try configureIdentity(in: seed)
        try commitSomething(in: seed)
        try git("push", "origin", "main", in: seed)

        let worktree = directory.appending(path: "bare-main")
        try git("worktree", "add", worktree.path(percentEncoded: false), "main", in: bare)

        let trees = try await client.worktrees(at: bare)
        #expect(trees.count == 1)
        #expect(trees.first?.checkout == .branch("main"))
        #expect(trees.first?.isMainWorkingTree == false)
    }

    @Test func worktreeWhoseFolderWasDeletedIsSkipped() async throws {
        let repository = try makeRepository("repo")
        let gone = directory.appending(path: "gone")
        try git("worktree", "add", gone.path(percentEncoded: false), "-b", "gone", in: repository)
        try FileManager.default.removeItem(at: gone)

        let trees = try await client.worktrees(at: repository)
        #expect(trees.map(\.checkout) == [.branch("main")])
    }

    @Test func nonRepositoriesAndLinkedWorktreesHaveNoWorktrees() async throws {
        let plain = try makeDirectory("plain")
        #expect(try await client.worktrees(at: plain).isEmpty)

        let repository = try makeRepository("repo")
        let linked = directory.appending(path: "linked")
        try git("worktree", "add", linked.path(percentEncoded: false), "-b", "linked", in: repository)
        #expect(try await client.worktrees(at: linked).isEmpty)
    }
}

/// The fake has to behave like the real thing, or tests written against it lie.
@Suite struct StubGitClientTests {
    let client = StubGitClient()

    @Test func unknownPathsAreNotRepositories() async throws {
        #expect(try await client.repositoryKind(at: URL(filePath: "/tmp/whatever")) == .notARepository)
    }

    @Test func seededPathsReportTheirKind() async throws {
        let url = URL(filePath: "/tmp/repo")
        client.seed(url, .mainWorkingTree)
        #expect(try await client.repositoryKind(at: url) == .mainWorkingTree)
    }

    @Test func theStubRecordsWhatWasAdded() async throws {
        let repository = URL(filePath: "/tmp/repo")
        let path = URL(filePath: "/tmp/repo/feature")

        try await client.addWorktree(in: repository, at: path, newBranch: "feature", from: "main")

        #expect(client.addedWorktrees == [
            .init(repository: repository, path: path, newBranch: "feature", base: "main")
        ])
    }

    @Test func theStubCanRefuseToAdd() async {
        client.failAddingWorktrees(with: "nope")

        await #expect(throws: GitClientError.commandFailed("nope")) {
            try await client.addWorktree(
                in: URL(filePath: "/tmp/repo"),
                at: URL(filePath: "/tmp/x"),
                newBranch: "x",
                from: "main"
            )
        }
    }

    @Test func seededBranchesComeBack() async throws {
        let url = URL(filePath: "/tmp/repo")
        client.seed(branches: ["a", "main"], at: url)
        #expect(try await client.branches(at: url) == ["a", "main"])
    }

    @Test func seededWorktreesComeBackInOrder() async throws {
        let url = URL(filePath: "/tmp/repo")
        let trees = [GitWorktree(path: url, checkout: .branch("main"), isMainWorkingTree: true)]
        client.seed(worktrees: trees, at: url)
        #expect(try await client.worktrees(at: url) == trees)
        #expect(try await client.worktrees(at: URL(filePath: "/tmp/other")).isEmpty)
    }
}
