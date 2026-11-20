#if DEBUG
import Core
import Foundation
import Synchronization

/// `GitClient` whose answers are set by the test, so no test needs a real
/// repository on disk.
///
/// All state sits behind a lock because Swift Testing runs tests in parallel.
public final class StubGitClient: GitClient {
    private let kinds = Mutex<[String: GitRepositoryKind]>([:])
    private let trees = Mutex<[String: [GitWorktree]]>([:])
    private let branchLists = Mutex<[String: [String]]>([:])
    private let added = Mutex<[AddedWorktree]>([])
    private let addFailure = Mutex<String?>(nil)
    private let fetchBases = Mutex<[String: String?]>([:])
    private let fetched = Mutex<[URL]>([])
    private let fetchFailure = Mutex<String?>(nil)
    private let unreadable = Mutex<Set<String>>([])
    private let gitDirectories = Mutex<[String: URL?]>([:])
    private let checkouts = Mutex<[String: GitWorktree.Checkout?]>([:])
    private let statuses = Mutex<[String: [String: GitStatus]]>([:])
    private let statusAsked = Mutex<[URL]>([])
    private let summaries = Mutex<[String: GitChangeSummary?]>([:])
    private let changesAsked = Mutex<[URL]>([])
    private let changesFail = Mutex(false)
    private let committed = Mutex<[ContentKey: String?]>([:])
    private let contentsAsked = Mutex<[URL]>([])
    private let contentsFail = Mutex(false)
    private let statusFails = Mutex(false)
    private let statusHeld = Mutex(false)
    private let statusWaiter = Mutex<CheckedContinuation<Void, Never>?>(nil)
    private let mergeBases = Mutex<[String: String?]>([:])
    private let upstreams = Mutex<[String: String?]>([:])
    private let shortstats = Mutex<[String: GitChangeSummary?]>([:])
    private let changedLists = Mutex<[String: [GitChangedFile]]>([:])
    private let changedAsked = Mutex<[String]>([])
    private let refLists = Mutex<[String: [GitRef]]>([:])
    private let commitLists = Mutex<[String: [GitCommit]]>([:])
    private let commitLookups = Mutex<[String: GitCommit]>([:])

    private struct ContentKey: Hashable {
        var path: String
        var revision: String
    }

    /// A call to `addWorktree`, as the stub saw it.
    public struct AddedWorktree: Equatable, Sendable {
        public var repository: URL
        public var path: URL
        public var newBranch: String
        public var base: String

        public init(repository: URL, path: URL, newBranch: String, base: String) {
            self.repository = repository
            self.path = path
            self.newBranch = newBranch
            self.base = base
        }
    }

    public init() {}

    /// Declares the local branches of the repository at `url`.
    public func seed(branches: [String], at url: URL) {
        branchLists.withLock { $0[FolderKey.of(url)] = branches }
    }

    /// Makes `addWorktree` throw `commandFailed(message)`.
    public func failAddingWorktrees(with message: String) {
        addFailure.withLock { $0 = message }
    }

    /// Declares the ref `fetchDefaultBranch` names for the repository at `url`.
    /// Unseeded, there is none.
    public func seed(fetchedBase: String?, at url: URL) {
        fetchBases.withLock { $0[FolderKey.of(url)] = fetchedBase }
    }

    /// Makes `fetchDefaultBranch` throw `commandFailed(message)`.
    public func failFetching(with message: String) {
        fetchFailure.withLock { $0 = message }
    }

    /// Every repository `fetchDefaultBranch` was asked about, in order.
    public var fetchedRepositories: [URL] {
        fetched.withLock { $0 }
    }

    /// Every `addWorktree` call so far, in order.
    public var addedWorktrees: [AddedWorktree] {
        added.withLock { $0 }
    }

    /// Declares what git would say about `url`. Anything unseeded is
    /// `.notARepository`, matching a disk with nothing on it.
    public func seed(_ url: URL, _ kind: GitRepositoryKind) {
        kinds.withLock { $0[FolderKey.of(url)] = kind }
    }

    /// Declares the worktrees git would list for `url`, in display order.
    public func seed(worktrees: [GitWorktree], at url: URL) {
        trees.withLock { $0[FolderKey.of(url)] = worktrees }
    }

    /// Makes `worktrees(at:)` throw for `url`, as it would for a folder that
    /// vanished between being listed and being read.
    public func seedUnreadable(_ url: URL) {
        unreadable.withLock { _ = $0.insert(FolderKey.of(url)) }
    }

    /// Declares where the working tree at `worktree` keeps its index.
    public func seed(gitDirectory: URL?, of worktree: URL) {
        gitDirectories.withLock { $0[FolderKey.of(worktree)] = gitDirectory }
    }

    /// `<worktree>/.git` unless seeded otherwise, which is the layout of an
    /// ordinary repository.
    public func gitDirectory(of url: URL) async throws -> URL? {
        gitDirectories.withLock { $0[FolderKey.of(url)] } ?? url.appending(path: ".git")
    }

    /// Declares what the working tree at `worktree` has checked out. Replaces
    /// any earlier seed; unseeded, it has nothing.
    public func seed(checkout: GitWorktree.Checkout?, of worktree: URL) {
        checkouts.withLock { $0[FolderKey.of(worktree)] = checkout }
    }

    public func checkout(of url: URL) async throws -> GitWorktree.Checkout? {
        checkouts.withLock { $0[FolderKey.of(url)] } ?? nil
    }

    /// Declares what git would say about the working tree at `worktree`, keyed
    /// by path relative to it, the way porcelain output is. Replaces any
    /// earlier seed.
    public func seed(status: [String: GitStatus], in worktree: URL) {
        statuses.withLock { $0[PathKey(worktree).path] = status }
    }

    /// The common case: these paths, relative to `worktree`, are ignored and
    /// nothing else has changed.
    public func seed(ignored paths: Set<String>, in worktree: URL) {
        seed(status: Dictionary(uniqueKeysWithValues: paths.map { ($0, GitStatus.ignored) }), in: worktree)
    }

    /// Makes `status(in:)` throw, as it would if git could not run.
    public func failStatusLookups(_ fails: Bool = true) {
        statusFails.withLock { $0 = fails }
    }

    /// Makes `status(in:)` wait, once asked, until `releaseStatusLookups()`.
    public func holdStatusLookups() {
        statusHeld.withLock { $0 = true }
    }

    public func releaseStatusLookups() {
        statusHeld.withLock { $0 = false }
        statusWaiter.withLock { waiter in
            defer { waiter = nil }
            return waiter
        }?.resume()
    }

    /// Every working tree `status(in:)` has been asked about, in order.
    public var statusLookups: [URL] {
        statusAsked.withLock { $0 }
    }

    public func status(in worktree: URL) async throws -> GitWorktreeStatus {
        if statusHeld.withLock({ $0 }) {
            // Recorded once the wait is in place, so a test that sees the
            // lookup can release it without racing the wait.
            await withCheckedContinuation { waiter in
                statusWaiter.withLock { $0 = waiter }
                statusAsked.withLock { $0.append(worktree) }
            }
        } else {
            statusAsked.withLock { $0.append(worktree) }
        }
        if statusFails.withLock({ $0 }) { throw GitClientError.commandFailed("git could not run") }

        let root = PathKey(worktree)
        let seeded = statuses.withLock { $0[root.path] } ?? [:]
        return GitWorktreeStatus(
            root: root,
            entries: Dictionary(uniqueKeysWithValues: seeded.map { (root.appending($0.key), $0.value) })
        )
    }

    /// Declares the change summary for the working tree at `worktree`. Replaces
    /// any earlier seed; unseeded, there is none.
    public func seed(changes: GitChangeSummary?, in worktree: URL) {
        summaries.withLock { $0[FolderKey.of(worktree)] = changes }
    }

    /// Makes `changeSummary(in:)` throw, as it would if git could not run.
    public func failChangeLookups(_ fails: Bool = true) {
        changesFail.withLock { $0 = fails }
    }

    /// Every working tree `changeSummary(in:)` has been asked about, in order.
    public var changeLookups: [URL] {
        changesAsked.withLock { $0 }
    }

    public func changeSummary(in worktree: URL) async throws -> GitChangeSummary? {
        changesAsked.withLock { $0.append(worktree) }
        if changesFail.withLock({ $0 }) { throw GitClientError.commandFailed("git could not run") }
        return summaries.withLock { $0[FolderKey.of(worktree)] } ?? nil
    }

    /// Declares what `file` contained at `revision`. Unseeded, it was not
    /// there, which is `nil`; seeding `nil` says the same on purpose.
    public func seed(contents: String?, of file: URL, atRevision revision: String = "HEAD") {
        committed.withLock { $0[ContentKey(path: PathKey(file).path, revision: revision)] = contents }
    }

    /// Makes `contents(of:atRevision:in:)` throw, as it would if git could not run.
    public func failContentLookups(_ fails: Bool = true) {
        contentsFail.withLock { $0 = fails }
    }

    /// Every file `contents(of:atRevision:in:)` has been asked about, in order.
    public var contentLookups: [URL] {
        contentsAsked.withLock { $0 }
    }

    public func contents(of file: URL, atRevision revision: String, in worktree: URL) async throws -> String? {
        contentsAsked.withLock { $0.append(file) }
        if contentsFail.withLock({ $0 }) { throw GitClientError.commandFailed("git could not run") }
        return committed.withLock { $0[ContentKey(path: PathKey(file).path, revision: revision)] } ?? nil
    }

    /// Declares the merge-base of `HEAD` and `ref`. Unseeded, `ref` names
    /// nothing, which is `nil`; seeding `nil` says the same on purpose.
    public func seed(mergeBase: String?, of ref: String) {
        mergeBases.withLock { $0[ref] = mergeBase }
    }

    public func mergeBase(of ref: String, in worktree: URL) async throws -> String? {
        mergeBases.withLock { $0[ref] } ?? nil
    }

    /// Declares what the checked-out branch tracks, or the default branch.
    public func seed(upstream: String?, in worktree: URL) {
        upstreams.withLock { $0[FolderKey.of(worktree)] = upstream }
    }

    public func upstream(in worktree: URL) async throws -> String? {
        upstreams.withLock { $0[FolderKey.of(worktree)] } ?? nil
    }

    /// Declares the lines changed between `sha` and the working tree.
    public func seed(shortstat: GitChangeSummary?, since sha: String) {
        shortstats.withLock { $0[sha] = shortstat }
    }

    public func shortstat(since sha: String, in worktree: URL) async throws -> GitChangeSummary? {
        shortstats.withLock { $0[sha] } ?? nil
    }

    /// Declares the files changed between `sha` and the working tree.
    public func seed(changedFiles: [GitChangedFile], since sha: String) {
        changedLists.withLock { $0[sha] = changedFiles }
    }

    /// Every revision `changedFiles(since:in:)` has been asked about, in order.
    public var changedFileLookups: [String] {
        changedAsked.withLock { $0 }
    }

    public func changedFiles(since sha: String, in worktree: URL) async throws -> [GitChangedFile] {
        changedAsked.withLock { $0.append(sha) }
        return changedLists.withLock { $0[sha] } ?? []
    }

    public func seed(refs: [GitRef], in worktree: URL) {
        refLists.withLock { $0[FolderKey.of(worktree)] = refs }
    }

    public func refs(in worktree: URL) async throws -> [GitRef] {
        refLists.withLock { $0[FolderKey.of(worktree)] } ?? []
    }

    public func seed(commits: [GitCommit], in worktree: URL) {
        commitLists.withLock { $0[FolderKey.of(worktree)] = commits }
    }

    public func recentCommits(limit: Int, in worktree: URL) async throws -> [GitCommit] {
        Array((commitLists.withLock { $0[FolderKey.of(worktree)] } ?? []).prefix(limit))
    }

    /// Declares that `revision` names `commit`.
    public func seed(commit: GitCommit, matching revision: String) {
        commitLookups.withLock { $0[revision] = commit }
    }

    public func commit(matching revision: String, in worktree: URL) async throws -> GitCommit? {
        commitLookups.withLock { $0[revision] }
    }

    public func repositoryKind(at url: URL) async throws -> GitRepositoryKind {
        kinds.withLock { $0[FolderKey.of(url)] } ?? .notARepository
    }

    public func worktrees(at url: URL) async throws -> [GitWorktree] {
        if unreadable.withLock({ $0.contains(FolderKey.of(url)) }) {
            throw StubGitClientError.unreadable
        }
        return trees.withLock { $0[FolderKey.of(url)] } ?? []
    }

    public func branches(at url: URL) async throws -> [String] {
        branchLists.withLock { $0[FolderKey.of(url)] } ?? []
    }

    public func fetchDefaultBranch(in repository: URL) async throws -> String? {
        fetched.withLock { $0.append(repository) }
        if let message = fetchFailure.withLock({ $0 }) {
            throw GitClientError.commandFailed(message)
        }
        return fetchBases.withLock { $0[FolderKey.of(repository)] } ?? nil
    }

    public func addWorktree(
        in repository: URL,
        at path: URL,
        newBranch: String,
        from base: String
    ) async throws {
        if let message = addFailure.withLock({ $0 }) {
            throw GitClientError.commandFailed(message)
        }
        added.withLock {
            $0.append(AddedWorktree(repository: repository, path: path, newBranch: newBranch, base: base))
        }
    }
}

public enum StubGitClientError: Error, Equatable {
    case unreadable
}
#endif
