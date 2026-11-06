import SwiftUI

extension FocusedValues {
    /// Opens the add-repository modal in the window that has focus. Published
    /// by each window's root view, so a menu command lands in the right one.
    @Entry var beginAddingRepository: (() -> Void)?
}

/// The menu commands that act on a window.
///
/// Reads the focused window's action rather than holding a model of its own:
/// with a model per window there is no single place to send it, and "the
/// window in front" is what the user means.
public struct AppCommands: Commands {
    @FocusedValue(\.beginAddingRepository) private var beginAddingRepository

    public init() {}

    public var body: some Commands {
        // ⌘N already opens a new window.
        CommandGroup(after: .newItem) {
            Button("Add Repository…") { beginAddingRepository?() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(beginAddingRepository == nil)
        }
    }
}
