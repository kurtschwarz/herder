import DesignSystem
import SwiftUI

/// A terminal, drawn. Fills what it is given and tells the process how many
/// columns and rows that came to.
public struct TerminalView: NSViewRepresentable {
    private let screen: TerminalScreen

    /// Changes when the terminal should take the keyboard. A counter rather
    /// than a flag: asking twice has to work twice.
    private let focusRequest: Int

    /// Space between the edge and the grid. A full-screen program that lays
    /// out its own margins wants less than a shell does.
    private let inset: NSSize

    public init(
        screen: TerminalScreen,
        focusRequest: Int = 0,
        inset: NSSize = NSSize(width: Theme.Spacing.paneInset, height: Theme.Spacing.tight)
    ) {
        self.screen = screen
        self.focusRequest = focusRequest
        self.inset = inset
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        var handledFocusRequest = 0
    }

    public func makeNSView(context: Context) -> NSView {
        TerminalNSView(screen: screen, inset: inset)
    }

    public func updateNSView(_ view: NSView, context: Context) {
        guard focusRequest != context.coordinator.handledFocusRequest else { return }
        context.coordinator.handledFocusRequest = focusRequest
        // After this update: the view may not be in a window yet.
        DispatchQueue.main.async { screen.focus() }
    }
}
