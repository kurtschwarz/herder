import Core
import Darwin
import Foundation

/// Links the bundle's opencode items into opencode's config folder.
public struct LiveOpencodeIntegrationClient: OpencodeIntegrationClient {
    /// The bundle's `opencode` folder.
    let resources: URL
    /// opencode's config folder, `~/.config/opencode` by default.
    let config: URL

    public init(resources: URL, config: URL) {
        self.resources = resources
        self.config = config
    }

    /// Where opencode looks for its config. It honours `XDG_CONFIG_HOME`.
    /// This reads the app's environment, which a shell profile does not
    /// reach, so a user who sets it only there still gets `~/.config`.
    public static func configDirectory(environment: [String: String], home: URL) -> URL {
        let base = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory) }
            ?? home.appending(path: ".config", directoryHint: .isDirectory)
        return base.appending(path: "opencode", directoryHint: .isDirectory)
    }

    @concurrent
    public func install() async {
        for item in OpencodeIntegration.items {
            let source = resources.appending(path: item).path(percentEncoded: false)
            let place = config.appending(path: item).path(percentEncoded: false)
            let existing = Self.existing(at: place)
            guard existing != .link(destination: source, resolves: true),
                  OpencodeIntegration.shouldLink(over: existing),
                  FileManager.default.fileExists(atPath: source)
            else { continue }
            Self.link(place, to: source)
        }
    }

    static func existing(at path: String) -> OpencodeIntegration.Existing {
        let files = FileManager.default
        if let destination = try? files.destinationOfSymbolicLink(atPath: path) {
            return .link(destination: destination, resolves: files.fileExists(atPath: path))
        }
        return (try? files.attributesOfItem(atPath: path)) == nil ? .nothing : .item
    }

    /// Made beside `path` and renamed over it, so opencode starting at the
    /// same moment finds the old link or the new one, never neither.
    private static func link(_ path: String, to source: String) {
        let files = FileManager.default
        let folder = (path as NSString).deletingLastPathComponent
        let staging = (folder as NSString).appendingPathComponent(".herder-\(UUID().uuidString)")
        do {
            try files.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try files.createSymbolicLink(atPath: staging, withDestinationPath: source)
        } catch {
            return
        }
        if rename(staging, path) != 0 { try? files.removeItem(atPath: staging) }
    }
}
