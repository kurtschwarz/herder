import Foundation

/// Asks the user to choose a folder.
///
/// Under the sandbox this is the only way to get a folder the app may touch: a
/// path typed or pasted grants nothing, while a URL handed back by the open
/// panel carries the user's permission and can be turned into a bookmark.
public protocol FolderPickerClient: Sendable {
    /// The folder the user chose, or `nil` if they cancelled. `startingAt` is
    /// where the panel opens, which is how the app points the user at a folder
    /// it cannot reach itself.
    ///
    /// Main actor because the panel is AppKit UI; the rest of this module stays
    /// free of actor isolation.
    @MainActor
    func pickFolder(startingAt: URL?) async -> URL?
}
