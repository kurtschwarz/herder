import AppKit
import Core
import DesignSystem
import SwiftUI

/// The ⌘L pill and the selection prompt over one buffer's pane.
///
/// Overlays on the pane, not in the text view and not a popover: the text view
/// lays out its own subviews, and a popover would float over the window rather
/// than sit with the text. They are placed from where the text is each time it
/// scrolls or the pane is laid out, which is what makes them move with it.
final class SelectionPromptController {
    /// How long a selection has to stay put before the pill shows.
    static let settleDelay = Duration.milliseconds(250)

    var context: SelectionPromptContext?

    /// What was typed and not sent, for the next time the prompt opens.
    /// Memory only: gone with the buffer.
    private(set) var draft = ""

    private weak var textView: NSTextView?
    private weak var pane: CodePane?
    private let text: () -> String

    private var pill: NSHostingView<SelectionPill>?
    private var prompt: PromptHostingView?
    private var state: SelectionPromptState?

    /// The lines and range the prompt was opened on, frozen.
    private var frozen: (range: NSRange, lines: SelectedLines)?

    private var settling: Task<Void, Never>?

    var isOpen: Bool { prompt != nil }

    init(text: @escaping () -> String) {
        self.text = text
    }

    func attach(to pane: CodePane, textView: NSTextView) {
        self.pane = pane
        self.textView = textView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification,
            object: pane.scrollView.contentView
        )
    }

    // MARK: - Hearing about the text

    /// The selection moved, or was made. Mid-drag included.
    func selectionDidChange() {
        hidePill()
        if let frozen, textView?.selectedRange() != frozen.range { close() }
        guard !isOpen, let range = textView?.selectedRange(), range.length > 0, context != nil else { return }
        settle()
    }

    /// The text changed, which makes both the pill and the frozen lines stale.
    func textDidChange() {
        hidePill()
        close()
    }

    /// A click in the editor.
    func mouseDown() {
        hidePill()
        close()
    }

    /// Waits for the selection to stop moving, and for the mouse to come up.
    private func settle() {
        settling?.cancel()
        settling = Task { [weak self] in
            while true {
                try? await Task.sleep(for: Self.settleDelay)
                guard !Task.isCancelled else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 { break }
            }
            self?.showPill()
        }
    }

    // MARK: - The pill

    private func showPill() {
        guard !isOpen, let pane, let textView, let range = selection(of: textView), range.length > 0 else { return }
        let pill = self.pill ?? NSHostingView(rootView: SelectionPill { [weak self] in self?.open() })
        self.pill = pill
        if pill.superview == nil { pane.addSubview(pill) }
        layoutOverlays()
    }

    private func hidePill() {
        settling?.cancel()
        pill?.removeFromSuperview()
        pill = nil
    }

    // MARK: - The prompt

    /// ⌘L: opens the prompt on the selection, or on the line the caret is in;
    /// or closes it if it is open.
    func toggle() {
        if isOpen { close() } else { open() }
    }

    private func open() {
        guard let context, let pane, let textView, let range = selection(of: textView) else { return }
        hidePill()
        let lines = SelectedLines(of: range, in: text())
        let state = SelectionPromptState(
            ref: CodeRef(file: context.file, worktree: context.worktree?.root, selection: lines, isUnsaved: context.isUnsaved),
            feedback: draft
        )
        let view = SelectionPrompt(
            state: state,
            open: context.sessions,
            worktree: context.worktree?.id,
            send: { [weak self] action, session in self?.send(action, to: session) },
            startSession: { [weak self] in self?.startSession() },
            close: { [weak self] in self?.close() }
        )
        let prompt = PromptHostingView(rootView: view)
        prompt.onResize = { [weak self] in self?.layoutOverlays() }
        self.state = state
        self.prompt = prompt
        frozen = (range, lines)
        pane.addSubview(prompt)
        layoutOverlays()
    }

    /// Closes the prompt, keeping what was typed for next time, and gives the
    /// keyboard back to the text if the prompt had it.
    func close() {
        guard let prompt else { return }
        if let state { draft = state.feedback }
        returnFocus()
        prompt.removeFromSuperview()
        self.prompt = nil
        state = nil
        frozen = nil
    }

    private func returnFocus() {
        guard let textView, let window = textView.window, let prompt else { return }
        if let responder = window.firstResponder as? NSView, responder.isDescendant(of: prompt) {
            window.makeFirstResponder(textView)
        }
    }

    private func send(_ action: SelectionMessage.Action, to session: AgentSession) {
        guard let context, let state else { return }
        let message = SelectionMessage(action, ref: state.ref, feedback: state.feedback)
        context.send(session.id, text: message.text, submit: message.submit)
        context.show(session, takingFocus: false)
        state.feedback = ""
        close()
    }

    private func startSession() {
        guard let id = context?.worktree?.id else { return }
        let start = context?.start
        close()
        start?(id)
    }

    // MARK: - Placement

    @objc private func scrolled(_ note: Notification) {
        layoutOverlays()
    }

    /// Puts the pill and the prompt where the text they belong to is now.
    /// Closes the prompt if that has scrolled out of sight.
    func layoutOverlays() {
        guard let pane, let textView else { return }
        let visible = pane.scrollView.frame

        if let frozen, let prompt {
            guard
                let first = rect(at: frozen.range.location, in: textView),
                let last = rect(at: lastLineOffset(of: frozen.range), in: textView)
            else { return }
            if !first.union(last).intersects(visible) {
                close()
                return
            }
            let size = prompt.fittingSize
            let gap: CGFloat = 4
            var y = last.minY - gap - size.height
            if y < visible.minY {
                y = first.maxY + gap
                if y + size.height > visible.maxY { y = max(visible.minY, visible.maxY - size.height) }
            }
            let frame = NSRect(origin: NSPoint(x: visible.minX + Theme.Spacing.normal, y: y), size: size)
            if prompt.frame != frame { prompt.frame = frame }
        }

        if let pill, let range = selection(of: textView), range.length > 0,
           let end = rect(at: anchor(of: range), in: textView)
        {
            let size = pill.fittingSize
            let x = min(end.maxX + Theme.Spacing.normal, visible.maxX - size.width)
            let origin = NSPoint(x: max(visible.minX, x), y: end.midY - size.height / 2)
            if visible.contains(NSPoint(x: origin.x, y: end.midY)) {
                let frame = NSRect(origin: origin, size: size)
                if pill.frame != frame { pill.frame = frame }
            } else {
                hidePill()
            }
        }
    }

    /// The first range only: with several, the others are not asked about.
    private func selection(of textView: NSTextView) -> NSRange? {
        textView.selectedRanges.first?.rangeValue
    }

    /// Where the pill goes: the end of the selection, or the end of the line
    /// before it when the selection takes the line break and stops at the
    /// start of the next.
    private func anchor(of range: NSRange) -> Int {
        let string = text() as NSString
        let end = NSMaxRange(range)
        if range.length > 0, end > 0, end <= string.length, string.character(at: end - 1) == 0x0A { return end - 1 }
        return end
    }

    /// An offset on the last line the range touches.
    private func lastLineOffset(of range: NSRange) -> Int {
        let end = NSMaxRange(range)
        return range.length > 0 ? max(range.location, anchor(of: range)) : end
    }

    /// The caret's frame at `offset`, in this pane's coordinates.
    private func rect(at offset: Int, in textView: NSTextView) -> NSRect? {
        guard
            let pane,
            let layout = textView.textLayoutManager,
            let content = layout.textContentManager,
            let location = content.location(content.documentRange.location, offsetBy: offset)
        else { return nil }
        var frame: NSRect?
        layout.enumerateTextSegments(in: NSTextRange(location: location), type: .standard, options: []) { _, segment, _, _ in
            frame = segment
            return false
        }
        guard var frame else { return nil }
        frame.origin.x += textView.textContainerOrigin.x
        frame.origin.y += textView.textContainerOrigin.y
        return pane.convert(frame, from: textView)
    }
}

/// Hosts the prompt, and says when it wants another size: the field grows as
/// more is typed.
private final class PromptHostingView: NSHostingView<SelectionPrompt> {
    var onResize: () -> Void = {}

    required init(rootView: SelectionPrompt) {
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onResize()
    }
}
