import Foundation

/// The user's `settings.json`: reading it, writing it and hearing that it
/// changed.
///
/// Knows nothing about what is in it. ``UserSettingsStore`` decodes, encodes,
/// debounces and ignores its own writes coming back.
public protocol SettingsFileClient: Sendable {
    /// Where the file is, whether or not it exists.
    var url: URL { get }

    /// The file's text, or `nil` when there is no file.
    func read() async throws -> String?

    /// Replaces the file with `contents`, atomically, making its folder if it
    /// has none.
    func write(_ contents: String) async throws

    /// Something in the file's folder may have changed, the file included.
    /// The folder rather than the file, so an editor that saves by writing a
    /// new file over the old one is still heard. Ends when the task awaiting
    /// it is cancelled.
    func changes() -> AsyncStream<Void>
}
