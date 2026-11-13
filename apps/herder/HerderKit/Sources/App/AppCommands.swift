import Core
import SwiftUI

extension FocusedValues {
    /// Opens the add-repository modal in the window that has focus. Published
    /// by each window's root view, so a menu command lands in the right one.
    @Entry var beginAddingRepository: (() -> Void)?

    /// Opens an untitled editor tab in the focused window. `nil` when it is
    /// showing no workspace.
    @Entry var newEditorFile: (() -> Void)?

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

    /// Show or hide the terminal panel, and move into it when it opens. `nil`
    /// with no workspace showing, since a terminal starts in one.
    @Entry var toggleTerminal: (() -> Void)?

    /// Start a shell in the workspace showing.
    @Entry var newTerminalTab: (() -> Void)?

    /// Start an agent session in the workspace showing.
    @Entry var newAgentSession: (() -> Void)?
}

/// The menu commands that act on a window.
///
/// Reads the focused window's action rather than holding a model of its own:
/// with a model per window there is no single place to send it, and "the
/// window in front" is what the user means.
public struct AppCommands: Commands {
    @FocusedValue(\.beginAddingRepository) private var beginAddingRepository
    @FocusedValue(\.newEditorFile) private var newEditorFile
    @FocusedValue(\.closeEditorTab) private var closeEditorTab
    @FocusedValue(\.saveEditorFile) private var saveEditorFile
    @FocusedValue(\.selectPreviousEditorTab) private var selectPreviousEditorTab
    @FocusedValue(\.selectNextEditorTab) private var selectNextEditorTab
    @FocusedValue(\.moveEditorTabLeft) private var moveEditorTabLeft
    @FocusedValue(\.moveEditorTabRight) private var moveEditorTabRight
    @FocusedValue(\.toggleTerminal) private var toggleTerminal
    @FocusedValue(\.newTerminalTab) private var newTerminalTab
    @FocusedValue(\.newAgentSession) private var newAgentSession
    @Environment(\.openWindow) private var openWindow

    private let updater: (any UpdaterClient)?

    public init(updater: (any UpdaterClient)?) {
        self.updater = updater
    }

    public var body: some Commands {
        // Under About, where a Mac app keeps it.
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater?.checkForUpdates() }
                .disabled(updater == nil)
        }

        // The settings window is a `Window` scene rather than SwiftUI's
        // `Settings`, which keeps a title bar that this design hides.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow(id: SettingsWindow.id) }
                .keyboardShortcut(",", modifiers: .command)
        }

        // ⌘N is a new file, so the window the scene gives itself moves to ⌃⌘N.
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: MainWindow.id) }
                .keyboardShortcut("n", modifiers: [.command, .control])

            Divider()

            Button("New File") { newEditorFile?() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newEditorFile == nil)

            Button("Add Repository…") { beginAddingRepository?() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(beginAddingRepository == nil)

            Button("New Terminal Tab") { newTerminalTab?() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(newTerminalTab == nil)

            Button("New Agent Session") { newAgentSession?() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(newAgentSession == nil)

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

        // Where View menus keep what shows and hides panels.
        CommandGroup(after: .sidebar) {
            Button("Toggle Terminal") { toggleTerminal?() }
                .keyboardShortcut("`", modifiers: .control)
                .disabled(toggleTerminal == nil)
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
