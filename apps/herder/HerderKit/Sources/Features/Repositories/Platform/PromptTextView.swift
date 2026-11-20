import AppKit
import DesignSystem
import SwiftUI

/// A plain, growing text input over `NSTextView`, for the New order card.
///
/// Not a SwiftUI `TextField`: that is an `NSTextField`, and AppKit's AutoFill
/// guesses at one and opens an empty suggestions panel under it when it is
/// clicked. A text view is never guessed at. It also puts Shift-Return's
/// newline at the caret, which a key handler over a `TextField` cannot.
///
/// Grows to `maxLines`, then scrolls. Return calls `submit`; Shift-Return
/// starts a new line.
struct PromptTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable = true
    var maxLines = 4
    /// Changes when the view should take the keyboard.
    var focusRequest = 0
    var submit: () -> Void

    static let font = NSFont.systemFont(ofSize: 13)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.font = Self.font
        textView.textColor = NSColor(Theme.Palette.text)
        textView.insertionPointColor = NSColor(Theme.Palette.text)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text }
        textView.isEditable = isEditable
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            textView.window?.makeFirstResponder(textView)
        }
    }

    /// One line high when empty, then as tall as the text up to `maxLines`.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView scrollView: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite,
              let textView = scrollView.documentView as? NSTextView,
              let container = textView.textContainer, let layout = textView.layoutManager
        else { return nil }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let line = layout.defaultLineHeight(for: Self.font)
        let used = layout.usedRect(for: container).height
        let height = min(max(used, line), line * CGFloat(maxLines))
        return CGSize(width: width, height: ceil(height))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptTextView
        var focusRequest: Int

        init(_ parent: PromptTextView) {
            self.parent = parent
            self.focusRequest = parent.focusRequest
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                parent.submit()
            }
            return true
        }
    }
}
