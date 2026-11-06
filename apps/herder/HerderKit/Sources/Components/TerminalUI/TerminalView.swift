import SwiftUI

/// A terminal, drawn. Fills what it is given and tells the process how many
/// columns and rows that came to.
public struct TerminalView: NSViewRepresentable {
    private let screen: TerminalScreen

    /// Changes when the terminal should take the keyboard. A counter rather
    /// than a flag: asking twice has to work twice.
    private let focusRequest: Int

    public init(screen: TerminalScreen, focusRequest: Int = 0) {
        self.screen = screen
        self.focusRequest = focusRequest
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        var handledFocusRequest = 0
    }

    public func makeNSView(context: Context) -> NSView {
        TerminalNSView(screen: screen)
    }

    public func updateNSView(_ view: NSView, context: Context) {
        guard focusRequest != context.coordinator.handledFocusRequest else { return }
        context.coordinator.handledFocusRequest = focusRequest
        // After this update: the view may not be in a window yet.
        DispatchQueue.main.async { screen.focus() }
    }
}
