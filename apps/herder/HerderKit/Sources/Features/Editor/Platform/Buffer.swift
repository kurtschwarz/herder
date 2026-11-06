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

    /// Made on first use: a restored window with fifteen tabs shows one.
    private(set) lazy var pane: CodePane = makePane()

    var text: String { storage.string }

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
        textView?.setSelectedRange(NSRange(location: 0, length: 0))
        gutter?.textDidChange(to: text)
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
        let textView = NSTextView(frame: .zero, textContainer: container)
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
        self.textView = textView
        self.gutter = gutter
        return CodePane(scrollView: scrollView, gutter: gutter)
    }

    /// The view that takes the keyboard when this tab is shown.
    var responder: NSView? { textView }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        gutter?.textDidChange(to: storage.string)
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
