/// Where a watcher had got to in the file system's event history.
///
/// Opaque: only the watcher knows what the number means. Kept so a stream can
/// be started again from where the last one stopped and replay what happened
/// in between.
public struct FileWatcherPosition: Sendable, Equatable, Hashable {
    public var raw: UInt64

    public init(raw: UInt64) {
        self.raw = raw
    }
}
