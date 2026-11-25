import AppKit
import SwiftUI

/// Shows one tab's ``Buffer``: an editable text view with a line-number gutter.
///
/// TextKit 2 under an `NSScrollView`: contiguous selection, copy and find come
/// with it. Lines do not wrap, so a gutter number is one per line.
///
/// This only mounts. The text, the undo history and the scroll position belong
/// to the buffer, so showing another tab is swapping which pane sits in here,
/// and coming back finds everything as it was left.
struct CodeTextView: NSViewRepresentable {
    let buffer: Buffer

    /// What the selection prompt reaches out to, which the buffer cannot see.
    /// `nil` for a buffer with no prompt.
    let prompt: SelectionPromptContext?

    func makeNSView(context: Context) -> PaneHost {
        PaneHost()
    }

    func updateNSView(_ host: PaneHost, context: Context) {
        buffer.selectionPrompt.context = prompt
        host.show(buffer)
    }
}

/// Holds whichever pane is showing.
final class PaneHost: NSView {
    private var shown: CodePane?
    private weak var shownBuffer: Buffer?

    func show(_ buffer: Buffer) {
        defer { buffer.takeFocusIfWanted(in: window) }
        let pane = buffer.pane
        guard pane !== shown else { return }
        shownBuffer = buffer

        // Typing continues across a tab switch only if the keyboard follows it.
        let hadFocus = window?.firstResponder.map(isInside) ?? false
        shown?.removeFromSuperview()
        shown = pane
        pane.frame = bounds
        pane.autoresizingMask = [.width, .height]
        addSubview(pane)

        if hadFocus, let responder = buffer.responder { window?.makeFirstResponder(responder) }
    }

    /// A pane mounted before its window existed, as in a window just
    /// opened, takes the keyboard it was asked for here.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        shownBuffer?.takeFocusIfWanted(in: window)
    }

    private func isInside(_ responder: NSResponder) -> Bool {
        guard let view = responder as? NSView, let shown else { return false }
        return view.isDescendant(of: shown)
    }
}
