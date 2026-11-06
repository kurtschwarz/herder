import Foundation
import TestSupport
import Testing

@testable import Core

/// Holding several worktrees open at once, and what that costs.
///
/// Before 4g the registry held exactly one: switching stopped the others and
/// dropped them, so coming back meant reading every folder again and anything
/// running in them would have been killed. These are about the rules that make
/// holding them all affordable.
@Suite @MainActor struct WorkspaceRegistryTests {
    let files = InMemoryFileClient()
    let git = StubGitClient()
    let watcher = StubFileWatcherClient()
    let clock = VirtualClockClient()
    let state = InMemoryStateStore()

    private let api = WorkspaceID(PathKey(canonical: "/code/api"))
    private let web = WorkspaceID(PathKey(canonical: "/code/web"))
    private let tools = WorkspaceID(PathKey(canonical: "/code/tools"))

    private func makeRegistry() -> WorkspaceRegistry {
        WorkspaceRegistry(files: files, git: git, watcher: watcher, clock: clock, state: state)
    }

    private func settle(yields: Int = 300) async {
        for _ in 0..<yields { await Task.yield() }
    }

    // MARK: - Opening and closing

    @Test func opensSeveralAtOnce() async throws {
        let registry = makeRegistry()

        await registry.open(api)
        await registry.open(web)
        await registry.open(tools)

        #expect(registry.workspaces.count == 3)
        #expect(registry.workspace(for: api) != nil)
        #expect(registry.workspace(for: web) != nil)
    }

    /// Opening one twice is free and hands back the same object, so a window
    /// switching back finds everything exactly as it was.
    @Test func openingTwiceIsTheSameWorkspace() async throws {
        let registry = makeRegistry()

        let first = try #require(await registry.open(api))
        let second = try #require(await registry.open(api))

        #expect(first === second)
        #expect(registry.workspaces.count == 1)
    }

    @Test func closingDropsOnlyThatOne() async throws {
        let registry = makeRegistry()
        await registry.open(api)
        await registry.open(web)

        await registry.close(api)

        #expect(registry.workspace(for: api) == nil)
        #expect(registry.workspace(for: web) != nil)
    }

    @Test func closingSomethingNotOpenIsHarmless() async throws {
        let registry = makeRegistry()
        await registry.close(api)
        #expect(registry.workspaces.isEmpty)
    }

    // MARK: - Draining

    /// The rule that makes holding several affordable: only what a window shows
    /// asks git anything.
    @Test func onlyTheDisplayedWorkspaceDrains() async throws {
        let registry = makeRegistry()
        let window = NSObject()
        files.seed(children: [], of: api.url)
        files.seed(children: [], of: web.url)
        let shown = try #require(await registry.open(api))
        let background = try #require(await registry.open(web))
        registry.display(api, from: window)
        await shown.refresh()
        await background.refresh()

        let before = git.statusLookups.count
        watcher.change([api.url, web.url])
        await settle()

        // One drain, for the one on screen, not two.
        #expect(git.statusLookups.count == before + 1)
    }

    /// Two windows, two workspaces on screen, both fresh.
    @Test func twoWindowsKeepTwoWorkspacesDraining() async throws {
        let registry = makeRegistry()
        let first = NSObject()
        let second = NSObject()
        files.seed(children: [], of: api.url)
        files.seed(children: [], of: web.url)
        let a = try #require(await registry.open(api))
        let b = try #require(await registry.open(web))
        registry.display(api, from: first)
        registry.display(web, from: second)
        await a.refresh()
        await b.refresh()

        let before = git.statusLookups.count
        watcher.change([api.url, web.url])
        await settle()

        #expect(git.statusLookups.count == before + 2)
    }

    /// Nothing drains while the app is behind something else, however many
    /// windows are showing something.
    @Test func nothingDrainsWhileTheAppIsNotInFront() async throws {
        let registry = makeRegistry()
        let window = NSObject()
        files.seed(children: [], of: api.url)
        let workspace = try #require(await registry.open(api))
        registry.display(api, from: window)
        await workspace.refresh()
        registry.setFrontmost(false)

        let before = git.statusLookups.count
        watcher.change([api.url])
        await settle()

        #expect(git.statusLookups.count == before)
    }

    /// A window that goes away stops keeping its workspace fresh, but does not
    /// close it: another window may still be showing it, and the state is still
    /// worth having.
    @Test func aWindowClosingStopsItsWorkspaceDrainingWithoutClosingIt() async throws {
        let registry = makeRegistry()
        let window = NSObject()
        files.seed(children: [], of: api.url)
        let workspace = try #require(await registry.open(api))
        registry.display(api, from: window)
        await workspace.refresh()

        registry.stopDisplaying(from: window)

        let before = git.statusLookups.count
        watcher.change([api.url])
        await settle()
        #expect(git.statusLookups.count == before)
        #expect(registry.workspace(for: api) != nil)
    }

    // MARK: - Holding

    /// A workspace lives while any window names it, so one window letting go
    /// of a checkout another is still on does not close it underneath.
    @Test func aWorkspaceStaysWhileAnotherHolderWantsIt() async throws {
        let registry = makeRegistry()
        let first = NSObject()
        let second = NSObject()
        let opened = await registry.open(api, holder: first)
        await registry.open(api, holder: second)

        await registry.close(api, holder: first)

        #expect(registry.workspace(for: api) === opened)
    }

    @Test func theLastHolderLettingGoClosesIt() async throws {
        let registry = makeRegistry()
        let first = NSObject()
        let second = NSObject()
        await registry.open(api, holder: first)
        await registry.open(api, holder: second)

        await registry.close(api, holder: first)
        await registry.close(api, holder: second)

        #expect(registry.workspace(for: api) == nil)
    }

    /// Closing without saying who is the old behaviour, and still drops it
    /// whoever holds it.
    @Test func closingOutrightIgnoresHolders() async throws {
        let registry = makeRegistry()
        await registry.open(api, holder: NSObject())

        await registry.close(api)

        #expect(registry.workspace(for: api) == nil)
    }

    /// A holder naming a workspace twice is one hold.
    @Test func holdingTwiceIsHoldingOnce() async throws {
        let registry = makeRegistry()
        let window = NSObject()
        await registry.open(api, holder: window)
        await registry.open(api, holder: window)

        await registry.close(api, holder: window)

        #expect(registry.workspace(for: api) == nil)
    }

    /// A window closing lets go of everything it held that no other window
    /// does, and nothing else.
    @Test func releasingAHolderKeepsWhatOthersHold() async throws {
        let registry = makeRegistry()
        let closing = NSObject()
        let staying = NSObject()
        await registry.open(api, holder: closing)
        await registry.open(web, holder: closing)
        await registry.open(web, holder: staying)

        await registry.release(holder: closing)

        #expect(registry.workspace(for: api) == nil)
        #expect(registry.workspace(for: web) != nil)
    }

    /// Switching away is not letting go: showing and holding are separate.
    @Test func displayingSomethingElseDoesNotLetGo() async throws {
        let registry = makeRegistry()
        let window = NSObject()
        await registry.open(api, holder: window)
        await registry.open(web, holder: window)
        registry.display(api, from: window)

        registry.display(web, from: window)

        #expect(registry.workspace(for: api) != nil)
    }

    /// The registry writes nothing about who holds what: that is each window's
    /// to record.
    @Test func openingWritesNothingToTheAppSnapshot() async throws {
        let registry = makeRegistry()

        await registry.open(api, holder: NSObject())

        #expect(try await state.load(AppSnapshot.self, forKey: AppSnapshot.persistenceKey) == nil)
    }
}
