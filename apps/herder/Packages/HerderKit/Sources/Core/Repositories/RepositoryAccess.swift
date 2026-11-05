import Foundation

/// Holds the sandbox's folder access open for as long as a repository is adopted.
///
/// Security-scoped access is a counted resource: every start needs exactly one
/// stop. Scoping it around each file operation would put that pairing on every
/// future caller, so it is taken once when a repository is opened and released
/// when it is removed or the app quits. One object owns the count, so there is
/// one place for it to be wrong.
public final class RepositoryAccess {
    private let bookmarks: any BookmarkClient
    private var urls: [UUID: URL] = [:]

    public init(bookmarks: any BookmarkClient) {
        self.bookmarks = bookmarks
    }

    /// Folders currently held open.
    public var openFolders: [UUID: URL] { urls }

    /// Takes access to `url` for `id`, replacing any access already held for it.
    /// Returns whether the sandbox granted it.
    @discardableResult
    public func begin(_ url: URL, for id: UUID) -> Bool {
        end(for: id)
        guard bookmarks.startAccessing(url) else { return false }
        urls[id] = url
        return true
    }

    public func end(for id: UUID) {
        guard let url = urls.removeValue(forKey: id) else { return }
        bookmarks.stopAccessing(url)
    }

    /// Releases everything, to balance what was taken at launch.
    public func endAll() {
        for id in urls.keys { end(for: id) }
    }
}
