import Core
import Foundation
import TestSupport
import Testing
import Worktrees

/// What the watcher must guarantee, driven by synthetic events so no test waits
/// for a real file system to settle.
@Suite struct WorktreeStateTests {
    let files = InMemoryFileClient()
    let git = StubGitClient()
    let watcher = StubFileWatcherClient()
    let clock = VirtualClockClient()
    let store: WorktreeStateStore
    let root = URL(filePath: "/code/api")

    init() {
        store = WorktreeStateStore(files: files, git: git, watcher: watcher, clock: clock)
    }

    func dir(_ name: String, in parent: URL? = nil) -> DirectoryEntry {
        DirectoryEntry(url: (parent ?? root).appending(path: name), isDirectory: true)
    }

    func file(_ name: String, in parent: URL? = nil) -> DirectoryEntry {
        DirectoryEntry(url: (parent ?? root).appending(path: name), isDirectory: false)
    }

    /// Opens `root` with `children` in it and reads it, the starting point for
    /// every test here.
    func start(with children: [DirectoryEntry] = []) async throws -> WorktreeState {
        files.seed(children: children, of: root)
        let state = try #require(await store.select(root))
        await state.refresh()
        return state
    }

    /// Lets the watcher's events be taken in and any drain run to the end.
    ///
    /// Yielding rather than sleeping: the clock is virtual, so every wait the
    /// drain does returns at once, and the only thing progress needs is a turn
    /// of the loop.
    /// `yields` has to outlast the number of batches sent: the stub hands them
    /// over one turn of the loop at a time, the way a real watcher does.
    func settle(yields: Int = 500) async {
        for _ in 0..<yields { await Task.yield() }
    }

    @Test func bothTheWorkingTreeAndTheIndexAreWatched() async throws {
        _ = try await start()

        // `git add` writes no file in the working tree at all, so without the
        // second root nothing would ever report a change to what is staged.
        #expect(watcher.watched == [[root, root.appending(path: ".git")]])
    }

    @Test func aFolderNotAWorkingTreeIsStillWatchedOnItsOwn() async throws {
        git.seed(gitDirectory: nil, of: root)
        _ = try await start()

        #expect(watcher.watched == [[root]])
    }

    @Test func aChangeToAFolderThatHasBeenReadReReadsIt() async throws {
        let state = try await start(with: [file("a.txt")])

        files.seed(children: [file("a.txt"), file("b.txt")], of: root)
        watcher.change([root])
        await settle()

        #expect(state.listing(of: state.root) == .loaded([file("a.txt"), file("b.txt")]))
    }

    /// The first and biggest filter. An install or a build writes thousands of
    /// files inside folders nobody has opened, and they have to cost nothing.
    @Test func changesInsideFoldersNobodyHasReadAreDropped() async throws {
        _ = try await start(with: [dir("node_modules")])
        let readsBefore = files.childReads.count
        let lookupsBefore = git.statusLookups.count

        watcher.change([root.appending(path: "node_modules")])
        watcher.change([root.appending(path: "node_modules/left-pad")])
        await settle()

        #expect(files.childReads.count == readsBefore)
        #expect(git.statusLookups.count == lookupsBefore)
    }

    /// The guardrail the whole design rests on: changes go into a set, and work
    /// per drain is bounded by how many folders are open rather than by how
    /// many events arrived.
    ///
    /// One drain in flight at a time, which is the other half of the guardrail:
    /// whatever arrives while a drain is out becomes exactly one more drain, no
    /// matter how much of it there is.
    @Test func changesArrivingDuringADrainCollapseIntoOneMore() async throws {
        _ = try await start(with: [file("a.txt")])
        let before = git.statusLookups.count
        git.holdStatusLookups()

        watcher.change([root])
        while git.statusLookups.count == before { await Task.yield() }

        for _ in 0..<1_000 {
            watcher.change([root])
        }
        await settle(yields: 5_000)
        // Still the one call: the drain that is out has not come back yet.
        #expect(git.statusLookups.count == before + 1)

        git.releaseStatusLookups()
        await settle()

        #expect(git.statusLookups.count == before + 2)
    }

    /// Nothing is drained while the window is away, so a storm that happens
    /// entirely behind the app's back — which is the usual case, the user being
    /// in the terminal that caused it — costs exactly one git call in the end.
    @Test func aStormWhileNobodyIsLookingCostsOneGitCall() async throws {
        let state = try await start(with: [file("a.txt")])
        let before = git.statusLookups.count
        state.setDraining(false)

        for _ in 0..<10_000 {
            watcher.change([root])
        }
        await settle(yields: 40_000)
        #expect(git.statusLookups.count == before)

        state.setDraining(true)
        await settle()

        #expect(git.statusLookups.count - before == 1)
    }

    /// How a real burst arrives: the file system batches it before any of this
    /// runs, so one callback can name every folder at once.
    @Test func oneBatchNamingEveryOpenFolderCostsOneGitCall() async throws {
        let folders = (0..<50).map { dir("folder\($0)") }
        for folder in folders {
            files.seed(children: [file("a.txt", in: folder.url)], of: folder.url)
        }
        let state = try await start(with: folders)
        for folder in folders { await state.open(PathKey(folder.url)) }
        let before = git.statusLookups.count

        watcher.change([root] + folders.map(\.url))
        await settle()

        #expect(git.statusLookups.count - before == 1)
    }

    @Test func aDrainWaitsForTheWritesToStop() async throws {
        _ = try await start(with: [file("a.txt")])

        watcher.change([root])
        await settle()

        #expect(clock.sleeps.contains(.milliseconds(150)))
    }

    /// A pure trailing debounce starves: a build that never goes quiet would
    /// hold the refresh off for as long as it ran.
    @Test func changesThatNeverGoQuietStillDrainWithinTheCeiling() async throws {
        _ = try await start(with: [file("a.txt")])
        let before = git.statusLookups.count
        let startedAt = clock.now

        // Long enough that the debounce alone would never have fired.
        while clock.now < startedAt.advanced(by: .seconds(3)), git.statusLookups.count == before {
            watcher.change([root])
            await Task.yield()
            await Task.yield()
        }

        #expect(git.statusLookups.count > before)
        #expect(clock.now < startedAt.advanced(by: .seconds(3)))
    }

    /// Nothing in the working tree moved, but what is staged may have, and the
    /// status call a drain makes anyway is the answer.
    @Test func aChangeToTheIndexAsksGitAgainWithoutReadingAnyFolder() async throws {
        _ = try await start(with: [file("a.txt")])
        let readsBefore = files.childReads.count
        let lookupsBefore = git.statusLookups.count

        watcher.change([root.appending(path: ".git")])
        await settle()

        #expect(files.childReads.count == readsBefore)
        #expect(git.statusLookups.count == lookupsBefore + 1)
    }

    /// The system admitting it dropped events, which degrades into exactly what
    /// a window coming forward always did.
    @Test func droppedEventsFallBackToReadingEverything() async throws {
        let sources = dir("Sources")
        files.seed(children: [file("a.swift", in: sources.url)], of: sources.url)
        let state = try await start(with: [sources])
        await state.open(PathKey(sources.url))
        let before = files.childReads.count

        watcher.dropEvents()
        await settle()

        // Both the root and the open folder, neither of which was named.
        #expect(files.childReads.count == before + 2)
    }

    @Test func aListingThatCameBackTheSameIsNotReplaced() async throws {
        let state = try await start(with: [file("a.txt")])
        let before = state.listing(of: state.root)

        // What a build in watch mode does: endless writes inside a folder whose
        // contents never change.
        for _ in 0..<50 { watcher.change([root]) }
        await settle()

        #expect(state.listing(of: state.root) == before)
    }

    /// `git worktree remove` in a terminal. The app's whole job is managing
    /// worktrees, so this is an ordinary Tuesday.
    @Test func aWorktreeRemovedFromUnderTheWatcherGoesUnavailable() async throws {
        let state = try await start(with: [file("a.txt")])

        watcher.vanish(root)
        await settle()

        #expect(!state.isAvailable)
        #expect(state.listings.isEmpty)
        // Nothing tries to read a half-dead tree.
        let before = files.childReads.count
        await state.refresh()
        #expect(files.childReads.count == before)
    }

    @Test func changesAccumulateWhileNobodyIsLookingAndAreActedOnWhenTheyAre() async throws {
        let state = try await start(with: [file("a.txt")])
        let before = git.statusLookups.count

        state.setDraining(false)
        files.seed(children: [file("a.txt"), file("b.txt")], of: root)
        watcher.change([root])
        await settle()

        #expect(git.statusLookups.count == before)

        state.setDraining(true)
        await settle()

        #expect(git.statusLookups.count == before + 1)
        #expect(state.listing(of: state.root) == .loaded([file("a.txt"), file("b.txt")]))
    }

    @Test func switchingWorktreeStopsWatchingTheOldOne() async throws {
        let other = URL(filePath: "/code/web")
        files.seed(children: [], of: other)
        let state = try await start(with: [file("a.txt")])

        await store.select(other)

        #expect(store.state(for: root) == nil)
        #expect(store.state(for: other) != nil)
        // The old state's watcher is cancelled, so its events go nowhere.
        let before = git.statusLookups.count
        watcher.change([root])
        await settle()
        #expect(git.statusLookups.count == before)
        #expect(state.listing(of: state.root) != nil)
    }

    @Test func comingBackToAWorktreeKeepsWhatWasAlreadyRead() async throws {
        let other = URL(filePath: "/code/web")
        files.seed(children: [], of: other)
        _ = try await start(with: [file("a.txt")])

        await store.select(other)
        let returned = try #require(await store.select(root))

        // A fresh state, because the old one stopped watching.
        #expect(returned.listing(returned.root) == nil)
    }

    /// Replaying from where the last stream stopped is the only thing that
    /// makes dropping a state and remaking it lossless.
    @Test func comingBackToAWorktreeReplaysWhatItMissed() async throws {
        let other = URL(filePath: "/code/web")
        files.seed(children: [], of: other)
        _ = try await start(with: [file("a.txt")])
        watcher.change([root])
        await settle()
        let reached = try #require(store.state(for: root)?.position)

        await store.select(other)
        await store.select(root)

        // Watched three times: this worktree blind, the other one blind, then
        // this one again from where it had got to.
        #expect(watcher.resumedFrom == [nil, nil, reached])
    }
}

private extension WorktreeState {
    /// Reads a listing by key without the test having to spell out the type.
    func listing(_ key: PathKey) -> Listing? { listing(of: key) }
}

@Suite struct WorktreeStateObserverTests {
    let files = InMemoryFileClient()
    let store: WorktreeStateStore
    let root = URL(filePath: "/code/api")

    init() {
        store = WorktreeStateStore(
            files: files,
            git: StubGitClient(),
            watcher: StubFileWatcherClient(),
            clock: VirtualClockClient()
        )
    }

    func start() async throws -> WorktreeState {
        files.seed(children: [DirectoryEntry(url: root.appending(path: "a.txt"), isDirectory: false)], of: root)
        let state = try #require(await store.select(root))
        await state.refresh()
        return state
    }

    @Test func everyObserverHearsAChange() async throws {
        let state = try await start()
        var heard = 0
        let first = state.observe(onChange: { heard += 1 })
        let second = state.observe(onChange: { heard += 1 })

        await state.refresh()

        #expect(heard == 2)
        first.cancel()
        second.cancel()
    }

    @Test func aCancelledObserverHearsNothing() async throws {
        let state = try await start()
        var heard = 0
        state.observe(onChange: { heard += 1 }).cancel()

        await state.refresh()

        #expect(heard == 0)
    }

    @Test func aMoveIsBroadcastWithTheOldAndNewPaths() async throws {
        let state = try await start()
        var moves: [[PathKey]] = []
        let registration = state.observe(onChange: {}, onMove: { moves.append([$0, $1]) })

        try await state.move(root.appending(path: "a.txt"), to: root.appending(path: "b.txt"))

        #expect(moves == [[PathKey(root.appending(path: "a.txt")), PathKey(root.appending(path: "b.txt"))]])
        registration.cancel()
    }

    @Test func existsSaysNilForAFolderNeverRead() async throws {
        let state = try await start()

        #expect(state.exists(state.root.appending("a.txt")) == true)
        #expect(state.exists(state.root.appending("gone.txt")) == false)
        #expect(state.exists(state.root.appending("sub/x.txt")) == nil)
    }
}
