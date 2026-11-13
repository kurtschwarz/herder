import Foundation

/// Asks the user where to save a new file.
public protocol SaveLocationClient: Sendable {
    /// The file the user chose to write, or `nil` if they cancelled. The panel
    /// opens in `directory` with `suggestedName` filled in; replacing a file
    /// that exists is confirmed by the panel itself.
    ///
    /// Main actor because the panel is AppKit UI; the rest of this module stays
    /// free of actor isolation.
    @MainActor
    func chooseSaveLocation(suggestedName: String, startingAt directory: URL) async -> URL?
}
