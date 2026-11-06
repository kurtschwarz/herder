import Foundation

/// Everything the app is allowed to do to the file system.
///
/// One example of the pattern every service follows: a protocol here that
/// features depend on, a live implementation in `Services/` that the composition
/// root injects, and a fake in `TestSupport/Fakes/` for tests and previews.
public protocol FileClient: Sendable {
    func read(_ path: String) async throws -> String

    /// Like ``read(_:)``, but never takes in more than `maxBytes`. Throws
    /// `tooLarge` for a longer file without reading the rest of it, and in the
    /// same call that does the reading, so a file that grows in between cannot
    /// slip past a size check made first.
    func read(_ path: String, maxBytes: Int) async throws -> String
    func write(_ contents: String, to path: String) async throws
    func exists(_ path: String) async -> Bool

    /// What is directly inside the folder at `url`, in no particular order.
    /// Throws for a folder that is missing or cannot be read.
    func children(of url: URL) async throws -> [DirectoryEntry]

    /// Moves the file or folder at `source` to `destination`. Throws
    /// `alreadyExists` rather than replacing what is there.
    func move(_ source: URL, to destination: URL) async throws

    /// Makes an empty file, or a folder, at `url`. Throws `alreadyExists`
    /// rather than replacing what is there.
    func create(_ url: URL, isDirectory: Bool) async throws

    /// Removes the file or folder at `url`, and everything inside a folder. With
    /// `permanently` false it goes to the Trash and can be put back; otherwise
    /// it is gone.
    func delete(_ url: URL, permanently: Bool) async throws
}
