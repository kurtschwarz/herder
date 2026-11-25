import AppKit
import Core
import DesignSystem
import os

/// One tab's text, and everything that has to outlive the tab being on screen:
/// the storage, the undo history, the layout, and the view showing them.
///
/// A buffer per tab rather than one view reused, because reusing a view loses
/// the undo stack, the selection and the scroll position of the tab left
/// behind. Here a tab switch only swaps which pane is mounted.
///
/// `Core` knows a buffer by its `BufferHandle` and whether its document is
/// dirty. What the text is, and what edited it, stays in here.
final class Buffer: NSObject, NSTextViewDelegate {
    let storage: NSTextStorage

    /// This tab's own. The window has one, shared by everything in it, and
    /// undoing in one tab must not undo in another.
    let undoManager = UndoManager()

    /// Called after the person using the view changed the text. Not called for
    /// ``replace(with:)`` or for colour.
    var onEdit: () -> Void = {}

    private let content = NSTextContentStorage()
    private let layout = NSTextLayoutManager()
    private let container = NSTextContainer()

    private static let signposter = OSSignposter(subsystem: "dev.herder", category: "editor")

    /// What is painted now, kept in step with the text as it is edited: see
    /// `TextEdit`. Parsing replaces it; typing only moves it.
    private var tokens: [SyntaxToken] = []

    private var textView: NSTextView?
    private var gutter: LineNumberGutter?
    private var whitespace: WhitespaceOverlay?

    /// Which whitespace is marked on screen. Never in the text.
    var showWhitespace = ShowWhitespace.none {
        didSet { whitespace?.mode = showWhitespace }
    }

    /// The ⌘L pill and the prompt it opens, with what was typed in it and not
    /// sent.
    private(set) lazy var selectionPrompt = SelectionPromptController { [unowned self] in storage.string }

    /// Made on first use: a restored window with fifteen tabs shows one.
    private(set) lazy var pane: CodePane = makePane()

    var text: String { storage.string }

    /// What `HEAD` has for this file, which the lines are compared with. `nil`
    /// when there is nothing to compare with. Set by whoever fetches it.
    var baseText: String?

    /// The lines that differ from ``baseText``, as last worked out for the text
    /// they were found in: see ``show(_:foundIn:)``.
    private(set) var changes = LineChanges.none

    init(text: String) {
        storage = NSTextStorage(string: text, attributes: SyntaxAttributes.base)
        super.init()
        content.textStorage = storage
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storageDidProcessEditing),
            name: NSTextStorage.didProcessEditingNotification,
            object: storage
        )
        content.addTextLayoutManager(layout)
        layout.textContainer = container
    }

    // MARK: - Writing into it

    /// Puts `text` in place of everything, as when the file changed on disk.
    /// The undo history goes too: its ranges mean nothing over different text.
    func replace(with text: String) {
        storage.setAttributedString(NSAttributedString(string: text, attributes: SyntaxAttributes.base))
        tokens = []
        edited = nil
        layout.removeRenderingAttribute(.foregroundColor, for: layout.documentRange)
        undoManager.removeAllActions()
        selectionPrompt.textDidChange()
        textView?.setSelectedRange(NSRange(location: 0, length: 0))
        gutter?.textDidChange(to: text)
        whitespace?.textDidChange()
    }

    // MARK: - Going to a place

    /// Puts the caret at `line` and `column`, both counting from one, and
    /// brings it into view. A place past the end of its line, or of the text,
    /// is the end of that line, or of the text.
    func reveal(line: Int, column: Int?) {
        let location = Self.offset(line: line, column: column, in: storage.string)
        let range = NSRange(location: location, length: 0)
        _ = pane
        textView?.setSelectedRange(range)
        scrollTarget = range
        scrollIfLaidOut()
    }

    /// Where the caret is, once there is a view to have one.
    var selectedRange: NSRange? { textView?.selectedRange() }

    /// The UTF-16 offset of `line` and `column` in `text`.
    static func offset(line: Int, column: Int?, in text: String) -> Int {
        let string = text as NSString
        var start = 0
        for _ in 1..<max(line, 1) {
            let next = NSMaxRange(string.lineRange(for: NSRange(location: start, length: 0)))
            // Past the last line, the last line.
            if next >= string.length { break }
            start = next
        }
        var contentsEnd = 0
        string.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
        return min(start + max((column ?? 1) - 1, 0), contentsEnd)
    }

    /// Where to scroll to once the pane has a size to scroll in: it is made
    /// when it is first shown, and has none until it is laid out.
    private var scrollTarget: NSRange?

    private func scrollIfLaidOut() {
        guard let range = scrollTarget, let textView, pane.bounds.height > 0 else { return }
        scrollTarget = nil
        textView.scrollRangeToVisible(range)
    }

    /// Colours the text as rendering attributes on the layout manager, not as
    /// attributes of the storage: they are not part of the text, so they are
    /// never an edit and never reach the undo stack.
    ///
    /// Only if the buffer still holds the `text` the tokens were found in.
    ///
    /// Only what differs from what is painted is touched: the tokens already
    /// on screen have followed the text through every edit, so a keystroke
    /// that changes one token repaints one. The text typed since the last
    /// paint is repainted as well, because that is where TextKit's idea of
    /// the colour and ours can differ.
    func colour(_ tokens: [SyntaxToken], foundIn text: String) {
        guard storage.string == text else { return }
        let changed = self.tokens.changedRange(to: tokens)
        self.tokens = tokens
        let range = [changed, edited].compactMap { $0 }.reduce(nil) { (union: NSRange?, next) in
            union.map { NSUnionRange($0, next) } ?? next
        }
        edited = nil
        if let range { paint(range) }
    }

    /// Hands the gutter `changes`, only if the buffer still holds the `text`
    /// they were found in: a result that outlived an edit would mark the wrong
    /// lines.
    func show(_ changes: LineChanges, foundIn text: String) {
        guard storage.string == text, self.changes != changes else { return }
        self.changes = changes
        gutter?.changes = changes
    }

    /// Paints the tokens that touch `range`, after clearing the colour there.
    private func paint(_ range: NSRange) {
        let range = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard range.length > 0, let cleared = textRange(range) else { return }

        let interval = Self.signposter.beginInterval("colour", "\(range.length) units")
        defer { Self.signposter.endInterval("colour", interval) }

        layout.removeRenderingAttribute(.foregroundColor, for: cleared)
        let length = storage.length

        for token in tokens
        where NSMaxRange(token.range) <= length
            && NSMaxRange(token.range) > range.location
            && token.range.location < NSMaxRange(range) {
            guard let painted = textRange(token.range) else { continue }
            layout.addRenderingAttribute(.foregroundColor, value: SyntaxAttributes.colour(for: token.kind), for: painted)
        }
        // Being no part of the text is why this has to be said out loud. TextKit
        // paints each paragraph into a view of its own inside the text view,
        // and a painted one keeps its pixels until that view is marked dirty.
        // An edit does that; a rendering attribute does not, nor does the text
        // view's own `needsDisplay`, which AppKit does not pass down, nor
        // invalidating layout, which reuses the views. Left alone, the colour
        // appeared when the caret next blinked, a second later, which read as
        // a slow highlighter.
        //
        // Only what is on screen has a view, so this is a few dozen at most;
        // the rest is painted with its colour as it scrolls in.
        textView.map(markForDisplay)
    }

    private func textRange(_ range: NSRange) -> NSTextRange? {
        guard
            let start = content.location(content.documentRange.location, offsetBy: range.location),
            let end = content.location(start, offsetBy: range.length)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }

    private func markForDisplay(_ view: NSView) {
        view.needsDisplay = true
        view.subviews.forEach(markForDisplay)
    }

    // MARK: - The view

    private func makePane() -> CodePane {
        let textView = SourceTextView(frame: .zero, textContainer: container)
        textView.delegate = self
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.typingAttributes = SyntaxAttributes.base
        // This is source, not prose: nothing may rewrite what was typed.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = textView.maxSize
        textView.textContainerInset = NSSize(width: Theme.Spacing.normal, height: Theme.Spacing.normal)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.clipsToBounds = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true

        let gutter = LineNumberGutter(scrollView: scrollView, textView: textView)
        gutter.textDidChange(to: storage.string)
        gutter.changes = changes
        let highlight = CurrentLineHighlight(scrollView: scrollView, textView: textView)
        let whitespace = WhitespaceOverlay(scrollView: scrollView, textView: textView)
        whitespace.mode = showWhitespace
        textView.onSelect = { [weak self, weak gutter, weak highlight] in
            gutter?.selectionDidChange()
            highlight?.selectionDidChange()
            self?.selectionPrompt.selectionDidChange()
        }
        textView.onPrompt = { [weak self] in self?.selectionPrompt.toggle() }
        textView.onMouseDown = { [weak self] in self?.selectionPrompt.mouseDown() }
        self.textView = textView
        self.gutter = gutter
        self.whitespace = whitespace
        let pane = CodePane(scrollView: scrollView, gutter: gutter, highlight: highlight, whitespace: whitespace)
        pane.onLayout = { [weak self] in
            self?.scrollIfLaidOut()
            self?.selectionPrompt.layoutOverlays()
        }
        selectionPrompt.attach(to: pane, textView: textView)
        return pane
    }

    /// The view that takes the keyboard when this tab is shown.
    var responder: NSView? { textView }

    /// The keyboard was asked for before the view was in a window, so the
    /// pane takes it once it is. See ``focus()``.
    private(set) var wantsFocus = false

    /// Gives this buffer the keyboard: now, if its view is in a window, or
    /// as soon as the pane puts it in one.
    func focus() {
        if let textView, let window = textView.window {
            window.makeFirstResponder(textView)
        } else {
            wantsFocus = true
        }
    }

    /// Takes the keyboard if it was asked for, now the view is in `window`.
    func takeFocusIfWanted(in window: NSWindow?) {
        guard wantsFocus, let window, let textView else { return }
        wantsFocus = false
        window.makeFirstResponder(textView)
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        gutter?.textDidChange(to: storage.string)
        whitespace?.textDidChange()
        selectionPrompt.textDidChange()
        onEdit()
    }

    // MARK: - Following edits

    /// The text changed since the last paint, in today's offsets. `nil` when
    /// none has.
    private var edited: NSRange?

    /// Moves ``tokens`` with the text, so they stay comparable with the next
    /// parse. TextKit moves what is on screen by itself; nothing is repainted
    /// here, which is what keeps a keystroke cheap.
    ///
    /// A notification rather than the storage's delegate: the content manager
    /// takes that over when the storage is attached to it.
    @objc private func storageDidProcessEditing(_ note: Notification) {
        guard storage.editedMask.contains(.editedCharacters), !tokens.isEmpty else { return }
        let range = storage.editedRange
        let edit = TextEdit(
            replaced: NSRange(location: range.location, length: range.length - storage.changeInLength),
            length: range.length
        )
        tokens = tokens.applying(edit)
        edited = edited.map { NSUnionRange(edit.carrying($0), range) } ?? range
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        undoManager
    }
}
