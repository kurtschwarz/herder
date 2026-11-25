import Core
import Foundation

/// `SettingsFileClient` over the real file, built on ``LiveFileClient`` and
/// ``LiveFileWatcherClient``.
///
/// Watches the file's folder rather than the file: an editor that saves by
/// writing a new file and renaming it over the old one replaces the file, and
/// a watch on the old one would hear nothing after the first save.
public struct LiveSettingsFileClient: SettingsFileClient {
    public let url: URL
    private let files = LiveFileClient()
    private let watcher = LiveFileWatcherClient()

    public init(url: URL) {
        self.url = url
    }

    /// `~/.config/herder/settings.json`, or under `$XDG_CONFIG_HOME` when that
    /// is set, as for opencode's config folder.
    public static func location(environment: [String: String], home: URL) -> URL {
        let base = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory) }
            ?? home.appending(path: ".config", directoryHint: .isDirectory)
        return base.appending(path: "herder", directoryHint: .isDirectory).appending(path: "settings.json")
    }

    private var path: String { url.path(percentEncoded: false) }
    private var folder: URL { url.deletingLastPathComponent() }

    public func read() async throws -> String? {
        do {
            return try await files.read(path)
        } catch FileClientError.notFound {
            return nil
        }
    }

    public func write(_ contents: String) async throws {
        try await files.write(contents, to: path)
    }

    /// The folder is made if it is missing, so there is something to watch
    /// before the file exists, and made again and watched afresh if it is
    /// deleted.
    public func changes() -> AsyncStream<Void> {
        let folder = folder
        let watcher = watcher
        return AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    for await batch in watcher.watch([folder], from: nil) {
                        continuation.yield()
                        if !batch.vanishedRoots.isEmpty { break }
                    }
                    // A watch that ended on its own, or a folder that could
                    // not be made, is not retried in a tight loop.
                    try? await Task.sleep(for: .seconds(1))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
