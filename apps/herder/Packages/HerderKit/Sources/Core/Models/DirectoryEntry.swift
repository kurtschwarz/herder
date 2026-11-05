import Foundation

/// One item inside a folder.
public struct DirectoryEntry: Sendable, Equatable, Identifiable {
    public var url: URL

    /// Follows symlinks, so a link to a folder reads as a folder.
    public var isDirectory: Bool

    public var id: URL { url }
    public var name: String { url.lastPathComponent }

    public init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }
}
