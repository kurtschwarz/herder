import CoreServices
import Foundation
import Models

/// `FileWatcherClient` over FSEvents.
///
/// The app is not sandboxed, so watching arbitrary folders of the user's needs
/// no entitlement work.
///
/// Two create flags carry the design. `NoDefer` makes the first event after a
/// quiet spell fire at once, so a single `touch` in a terminal shows up
/// immediately while the latency below acts as a cooldown on whatever follows
/// it — leading-edge batching, for free, before any of this app's code runs.
/// `WatchRoot` is what reports a worktree being moved or deleted, which is a
/// thing that happens here on purpose.
///
/// File-level events are deliberately *not* asked for: the default granularity
/// is the folder containing the change, which is both fewer events and exactly
/// what a tree acts on.
public struct LiveFileWatcherClient: FileWatcherClient {
    /// How long the system batches a burst before handing it over. Long enough
    /// that an install writing thousands of files arrives as a handful of
    /// callbacks, short enough to feel immediate — and with `NoDefer` it only
    /// ever delays the events *after* the first.
    static let latency: CFTimeInterval = 0.25

    public init() {}

    public func watch(_ roots: [URL], from position: FileWatcherPosition?) -> AsyncStream<FileChangeBatch> {
        // Unbounded on purpose. Dropping the oldest batch would drop the
        // folders it named, and the consumer keeps reading even while it has
        // stopped acting on what it reads, so nothing accumulates for long.
        AsyncStream { continuation in
            let session = WatchSession(roots: roots, from: position, continuation: continuation)
            continuation.onTermination = { _ in session.stop() }
            session.start()
        }
    }
}

/// One FSEvents stream and the continuation it feeds.
///
/// `@unchecked Sendable` under one rule: every mutable property is touched only
/// on `queue`, which is also the queue FSEvents calls back on.
private final class WatchSession: @unchecked Sendable {
    private let roots: [String]
    private let since: FSEventStreamEventId
    private let continuation: AsyncStream<FileChangeBatch>.Continuation
    private let queue = DispatchQueue(label: "ar.schw.herder.file-watcher")

    private var stream: FSEventStreamRef?
    private var isStopped = false

    init(roots: [URL], from position: FileWatcherPosition?, continuation: AsyncStream<FileChangeBatch>.Continuation) {
        self.roots = roots.map { PathKey($0).path }
        self.since = position.map { FSEventStreamEventId($0.raw) }
            ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        self.continuation = continuation
    }

    func startWatching() {
        guard !isStopped, !roots.isEmpty else {
            continuation.finish()
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            // Handed to C, so the session is retained by hand and let go in
            // `releaseSession` once FSEvents is finished with the stream.
            info: Unmanaged.passRetained(self).toOpaque(),
            retain: nil,
            release: releaseSession,
            copyDescription: nil
        )
        let flags = kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagWatchRoot
            | kFSEventStreamCreateFlagUseCFTypes

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            deliverEvents,
            &context,
            roots as CFArray,
            since,
            LiveFileWatcherClient.latency,
            FSEventStreamCreateFlags(flags)
        ) else {
            // Nothing to watch with. The tree still refreshes when the window
            // comes forward, so this degrades rather than breaking.
            Unmanaged<WatchSession>.fromOpaque(context.info!).release()
            continuation.finish()
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func start() {
        queue.async { self.startWatching() }
    }

    func stop() {
        queue.async {
            self.isStopped = true
            guard let stream = self.stream else { return }
            self.stream = nil
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            // Lets go of the retain taken for `context.info`, by way of
            // `releaseSession`.
            FSEventStreamRelease(stream)
            self.continuation.finish()
        }
    }

    func deliver(
        folders: Set<PathKey>,
        vanishedRoots: Set<PathKey>,
        needsFullScan: Bool,
        position: FSEventStreamEventId
    ) {
        guard !isStopped, !folders.isEmpty || !vanishedRoots.isEmpty || needsFullScan else { return }
        continuation.yield(FileChangeBatch(
            folders: folders,
            vanishedRoots: vanishedRoots,
            needsFullScan: needsFullScan,
            position: FileWatcherPosition(raw: position)
        ))
    }
}

/// Plain functions rather than closures: these are handed to C, which can hold
/// no context beyond the pointer in `FSEventStreamContext`.
private func deliverEvents(
    _ stream: ConstFSEventStreamRef,
    _ info: UnsafeMutableRawPointer?,
    _ count: Int,
    _ paths: UnsafeMutableRawPointer,
    _ flags: UnsafePointer<FSEventStreamEventFlags>,
    _ identifiers: UnsafePointer<FSEventStreamEventId>
) {
    guard let info, count > 0 else { return }
    let session = Unmanaged<WatchSession>.fromOpaque(info).takeUnretainedValue()
    // `UseCFTypes` is what makes this a CFArray of CFString rather than a bare
    // C array.
    guard let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] else { return }

    var folders: Set<PathKey> = []
    var vanished: Set<PathKey> = []
    var needsFullScan = false
    var position: FSEventStreamEventId = 0

    for index in 0..<min(count, paths.count) {
        let flag = Int(flags[index])
        position = max(position, identifiers[index])

        // The system saying it gave up: either queue overflowed, or it is
        // telling us outright to rescan.
        if flag & kFSEventStreamEventFlagMustScanSubDirs != 0
            || flag & kFSEventStreamEventFlagUserDropped != 0
            || flag & kFSEventStreamEventFlagKernelDropped != 0 {
            needsFullScan = true
            continue
        }
        // Carries no path worth reading: the marker that a replay finished, or
        // a change to the volume rather than to anything in it.
        if flag & kFSEventStreamEventFlagHistoryDone != 0 { continue }

        let key = PathKey(resolved: paths[index])
        if flag & kFSEventStreamEventFlagRootChanged != 0 {
            vanished.insert(key)
        } else {
            folders.insert(key)
        }
    }

    session.deliver(
        folders: folders,
        vanishedRoots: vanished,
        needsFullScan: needsFullScan,
        position: position
    )
}

private func releaseSession(_ info: UnsafeRawPointer?) {
    guard let info else { return }
    Unmanaged<WatchSession>.fromOpaque(info).release()
}
