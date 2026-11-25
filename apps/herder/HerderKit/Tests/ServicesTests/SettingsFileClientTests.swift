import Core
import Foundation
import Services
import Synchronization
import Testing
import TestSupport

/// Against a temporary folder, for what a fake cannot show: a missing file
/// reads as none, a write makes the folders, and an atomic replace is heard.
@Suite struct LiveSettingsFileClientTests {
    let root: URL
    let client: LiveSettingsFileClient

    init() {
        root = URL.temporaryDirectory.appending(path: "LiveSettingsFileClientTests/\(UUID().uuidString)")
        client = LiveSettingsFileClient(url: root.appending(path: "herder/settings.json"))
    }

    @Test func theFileIsUnderXDGConfigHomeOrDotConfig() {
        let home = URL(filePath: "/Users/kurt", directoryHint: .isDirectory)

        #expect(LiveSettingsFileClient.location(environment: [:], home: home).path(percentEncoded: false)
            == "/Users/kurt/.config/herder/settings.json")
        #expect(LiveSettingsFileClient.location(environment: ["XDG_CONFIG_HOME": "/tmp/xdg"], home: home)
            .path(percentEncoded: false) == "/tmp/xdg/herder/settings.json")
        #expect(LiveSettingsFileClient.location(environment: ["XDG_CONFIG_HOME": ""], home: home)
            .path(percentEncoded: false) == "/Users/kurt/.config/herder/settings.json")
    }

    @Test func aMissingFileIsNoneAndAWriteMakesItsFolder() async throws {
        #expect(try await client.read() == nil)

        try await client.write("{}\n")

        #expect(try await client.read() == "{}\n")
    }

    @Test func aReplaceInTheFolderIsHeard() async throws {
        try await client.write("{}\n")
        let heard = Mutex(0)
        let changes = client.changes()
        let listening = Task { for await _ in changes { heard.withLock { $0 += 1 } } }
        defer { listening.cancel() }
        // FSEvents takes a moment to arm.
        try await Task.sleep(for: .milliseconds(500))

        // What an editor saving atomically does: a new file renamed over.
        let folder = client.url.deletingLastPathComponent()
        let temporary = folder.appending(path: ".settings.json.tmp")
        try Data("{}".utf8).write(to: temporary)
        _ = try FileManager.default.replaceItemAt(client.url, withItemAt: temporary)

        try await eventually("the change is heard") { heard.withLock { $0 } > 0 }
    }
}
