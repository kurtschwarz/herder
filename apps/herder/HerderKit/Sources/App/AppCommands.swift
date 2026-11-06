import SwiftUI

extension FocusedValues {
    /// Opens the add-repository modal in the window that has focus. Published
    /// by each window's root view, so a menu command lands in the right one.
    @Entry var beginAddingRepository: (() -> Void)?

    /// Closes the editor tab showing in the focused window. `nil` when that
    /// window has none open, which is what leaves ⌘W closing the window.
    @Entry var closeEditorTab: (() -> Void)?

    /// Saves the file showing in the focused window. `nil` when it has no
    /// unsaved changes, so the item dims instead of rewriting what is there.
    @Entry var saveEditorFile: (() -> Void)?

    /// Cycle the focused window's editor tabs. `nil` with fewer than two, so
    /// the menu items read as unavailable rather than doing nothing.
    @Entry var selectPreviousEditorTab: (() -> Void)?
    @Entry var selectNextEditorTab: (() -> Void)?

    /// Move the tab showing one place along. `nil` when it is already at that
    /// end, so the item dims exactly when it would do nothing.
    @Entry var moveEditorTabLeft: (() -> Void)?
    @Entry var moveEditorTabRight: (() -> Void)?
}

/// The menu commands that act on a window.
///
/// Reads the focused window's action rather than holding a model of its own:
/// with a model per window there is no single place to send it, and "the
/// window in front" is what the user means.
public struct AppCommands: Commands {
    @FocusedValue(\.beginAddingRepository) private var beginAddingRepository
    @FocusedValue(\.closeEditorTab) private var closeEditorTab
    @FocusedValue(\.saveEditorFile) private var saveEditorFile
    @FocusedValue(\.selectPreviousEditorTab) private var selectPreviousEditorTab
    @FocusedValue(\.selectNextEditorTab) private var selectNextEditorTab
    @FocusedValue(\.moveEditorTabLeft) private var moveEditorTabLeft
    @FocusedValue(\.moveEditorTabRight) private var moveEditorTabRight

    public init() {}

    public var body: some Commands {
        // ⌘N already opens a new window.
        CommandGroup(after: .newItem) {
            Button("Add Repository…") { beginAddingRepository?() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(beginAddingRepository == nil)

            Divider()

            // Two items answer to ⌘W: this one and the window's own "Close".
            // AppKit walks the menus in order looking for a key equivalent and
            // skips the items that are disabled, and `after: .newItem` puts
            // this one above Close — so with tabs open ⌘W closes a tab, and
            // with none it closes the window. Safari's File menu, and the same
            // mechanism.
            Button("Close Tab") { closeEditorTab?() }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(closeEditorTab == nil)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") { saveEditorFile?() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(saveEditorFile == nil)
        }

        // Where an AppKit app puts tab navigation.
        CommandGroup(before: .windowList) {
            Button("Show Previous Tab") { selectPreviousEditorTab?() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(selectPreviousEditorTab == nil)

            Button("Show Next Tab") { selectNextEditorTab?() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(selectNextEditorTab == nil)

            // The navigation shortcuts with Option added.
            Button("Move Tab Left") { moveEditorTabLeft?() }
                .keyboardShortcut("[", modifiers: [.command, .option, .shift])
                .disabled(moveEditorTabLeft == nil)

            Button("Move Tab Right") { moveEditorTabRight?() }
                .keyboardShortcut("]", modifiers: [.command, .option, .shift])
                .disabled(moveEditorTabRight == nil)

            Divider()
        }
    }
}
