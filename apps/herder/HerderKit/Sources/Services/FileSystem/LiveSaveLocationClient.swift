import AppKit
import Core

/// `SaveLocationClient` backed by `NSSavePanel`.
public struct LiveSaveLocationClient: SaveLocationClient {
    public init() {}

    @MainActor
    public func chooseSaveLocation(suggestedName: String, startingAt directory: URL) async -> URL? {
        let panel = NSSavePanel()
        panel.directoryURL = directory
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true

        return panel.runModal() == .OK ? panel.url : nil
    }
}
