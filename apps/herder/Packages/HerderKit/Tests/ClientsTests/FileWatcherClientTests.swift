import Clients
import Foundation
import Models
import Synchronization
import Testing

/// Against the real file system, because what is worth testing here is the
/// FSEvents interop: the flags, the path marshalling, and the fact that a
/// change actually arrives. A fake would only test the fake.
@Suite struct LiveFileWatcherClientTests {
    let directory: URL
    let client = LiveFileWatcherClient()

    init() throws {
        directory = URL.temporaryDirectory
            .appending(path: "LiveFileWatcherClientTests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Batches as they arrive, so a test can wait for a condition rather than
    /// race a single `next()` against whichever batch the system sends first.
    final class Batches: @unchecked Sendable {
        private let received = Mutex<[FileChangeBatch]>([])

        func append(_ batch: FileChangeBatch) {
            received.withLock { $0.append(batch) }
        }

        var all: [FileChangeBatch] { received.withLock { $0 } }
        var folders: Set<PathKey> { Set(all.flatMap(\.folders)) }
        var vanished: Set<PathKey> { Set(all.flatMap(\.vanishedRoots)) }
    }

    func watch(_ roots: [URL]) -> (Batches, Task<Void, Never>) {
        let batches = Batches()
        let stream = client.watch(roots, from: nil)
        return (batches, Task { for await batch in stream { batches.append(batch) } })
    }

    /// FSEvents takes a moment to arm, and a change made before it is armed is
    /// not reported. Nothing in the app depends on that window, but a test
    /// writing immediately would.
    func armed() async throws {
        try await Task.sleep(for: .milliseconds(500))
    }

    func wait(for condition: @Sendable () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("the watcher reported nothing in time")
    }

    func make(_ name: String, in folder: URL) throws {
        try Data("x".utf8).write(to: folder.appending(path: name))
    }

    /// Also the regression guard for path spelling: the temporary directory is
    /// reached through `/var`, FSEvents reports it as `/private/var`, and the
    /// two only compare because `PathKey` resolves both.
    @Test func reportsTheFolderAFileWasMadeIn() async throws {
        let (batches, task) = watch([directory])
        defer { task.cancel() }
        try await armed()

        try make("a.txt", in: directory)

        try await wait { batches.folders.contains(PathKey(self.directory)) }
    }

    @Test func reportsAFolderDeepInsideTheTree() async throws {
        let deep = directory.appending(path: "a/b/c")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        let (batches, task) = watch([directory])
        defer { task.cancel() }
        try await armed()

        try make("found.txt", in: deep)

        try await wait { batches.folders.contains(PathKey(deep)) }
    }

    /// The case a worktree needs: a working tree and a git directory that is
    /// not inside it, on one stream.
    @Test func reportsChangesUnderEveryRootItWasGiven() async throws {
        let first = directory.appending(path: "tree")
        let second = directory.appending(path: "elsewhere")
        for url in [first, second] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let (batches, task) = watch([first, second])
        defer { task.cancel() }
        try await armed()

        try make("a.txt", in: first)
        try make("b.txt", in: second)

        try await wait {
            batches.folders.isSuperset(of: [PathKey(first), PathKey(second)])
        }
    }

    /// `git worktree remove` in a terminal, which is a thing this app exists to
    /// make happen.
    @Test func reportsARootThatWasTakenAway() async throws {
        let watched = directory.appending(path: "worktree")
        try FileManager.default.createDirectory(at: watched, withIntermediateDirectories: true)
        let (batches, task) = watch([watched])
        defer { task.cancel() }
        try await armed()

        try FileManager.default.removeItem(at: watched)

        try await wait { batches.vanished.contains(PathKey(canonical: PathKey(self.directory).path + "/worktree")) }
    }

    @Test func aStreamWithNothingToWatchEndsRatherThanHanging() async throws {
        var batches: [FileChangeBatch] = []
        for await batch in client.watch([], from: nil) { batches.append(batch) }

        #expect(batches.isEmpty)
    }
}

