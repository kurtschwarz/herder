#if DEBUG
import Core
import Foundation
import Synchronization

/// `BookmarkClient` for tests, so no test needs a sandbox or a real folder.
///
/// A bookmark here is the folder's path as bytes, which is what it resolves to
/// until a test redirects it. Tests can move a folder, make one stale or make one
/// unresolvable to drive the recovery paths, and can see which folders are
/// currently being accessed to check that access is balanced.
///
/// All state sits behind a lock because Swift Testing runs tests in parallel.
public final class InMemoryBookmarkClient: BookmarkClient {
    private struct State {
        /// Bookmark contents to the folder it currently resolves to.
        var resolutions: [String: String] = [:]
        var stale: Set<String> = []
        var broken: Set<String> = []
        var accessed: [String] = []
    }

    private let state = Mutex(State())

    public init() {}

    /// Resolution keeps working but reports the bookmark as needing to be remade.
    public func markStale(_ url: URL) {
        state.withLock { _ = $0.stale.insert(FolderKey.of(url)) }
    }

    /// Resolution fails, as it would for a deleted folder or an unmounted volume.
    public func breakResolution(for url: URL) {
        state.withLock { _ = $0.broken.insert(FolderKey.of(url)) }
    }

    /// Undoes `breakResolution(for:)`, for "the drive came back" cases.
    public func restoreResolution(for url: URL) {
        state.withLock { _ = $0.broken.remove(FolderKey.of(url)) }
    }

    /// The folder moved or was renamed: an existing bookmark now resolves
    /// somewhere else, which is the whole reason bookmarks beat paths.
    public func redirect(_ bookmark: Data, to url: URL) {
        state.withLock { $0.resolutions[String(decoding: bookmark, as: UTF8.self)] = FolderKey.of(url) }
    }

    /// Folders with access currently started, in the order they were started.
    public var accessedURLs: [URL] {
        state.withLock { $0.accessed }.map { URL(filePath: $0) }
    }

    public func makeBookmark(for url: URL) throws -> Data {
        let key = FolderKey.of(url)
        state.withLock {
            $0.resolutions[key] = key
            $0.stale.remove(key)
        }
        return Data(key.utf8)
    }

    public func resolve(_ bookmark: Data) throws -> ResolvedBookmark {
        let key = String(decoding: bookmark, as: UTF8.self)
        let resolved: (path: String, isStale: Bool)? = state.withLock {
            guard let path = $0.resolutions[key], !$0.broken.contains(path) else { return nil }
            return (path, $0.stale.contains(path))
        }
        guard let resolved else { throw BookmarkClientError.unresolvable }
        return ResolvedBookmark(url: URL(filePath: resolved.path), isStale: resolved.isStale)
    }

    public func startAccessing(_ url: URL) -> Bool {
        let key = FolderKey.of(url)
        return state.withLock {
            guard !$0.broken.contains(key) else { return false }
            $0.accessed.append(key)
            return true
        }
    }

    public func stopAccessing(_ url: URL) {
        let key = FolderKey.of(url)
        state.withLock {
            if let index = $0.accessed.firstIndex(of: key) {
                $0.accessed.remove(at: index)
            }
        }
    }
}
#endif
