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

    func makeNSView(context: Context) -> PaneHost {
        PaneHost()
    }

    func updateNSView(_ host: PaneHost, context: Context) {
        host.show(buffer)
    }
}

/// Holds whichever pane is showing.
final class PaneHost: NSView {
    private var shown: CodePane?

    func show(_ buffer: Buffer) {
        let pane = buffer.pane
        guard pane !== shown else { return }

        // Typing continues across a tab switch only if the keyboard follows it.
        let hadFocus = window?.firstResponder.map(isInside) ?? false
        shown?.removeFromSuperview()
        shown = pane
        pane.frame = bounds
        pane.autoresizingMask = [.width, .height]
        addSubview(pane)

        if hadFocus, let responder = buffer.responder { window?.makeFirstResponder(responder) }
    }

    private func isInside(_ responder: NSResponder) -> Bool {
        guard let view = responder as? NSView, let shown else { return false }
        return view.isDescendant(of: shown)
    }
}
