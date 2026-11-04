import AppKit

/// `FolderPickerClient` backed by `NSOpenPanel`. Injected from the app target.
public struct LiveFolderPickerClient: FolderPickerClient {
    public init() {}

    @MainActor
    public func pickFolder(startingAt: URL?) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = startingAt
        panel.prompt = "Choose"
        panel.message = "Choose a git repository to add as a workspace."

        return panel.runModal() == .OK ? panel.url : nil
    }
}
