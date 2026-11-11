import AppKit
import CoreText
import DesignSystem
import SwiftUI

/// Draws a ``TerminalEmulator``'s grid with Core Text, and turns the keyboard
/// and the mouse into what a terminal sends.
///
/// Draws by rows, so a program that rewrites one line repaints one line. All of
/// it is behind this one type: a Metal renderer, if `cat` of a large file ever
/// shows Core Text to be too slow, replaces this and nothing else.
final class TerminalNSView: NSView, NSUserInterfaceValidations {
    private let screen: TerminalScreen
    private var emulator: TerminalEmulator { screen.emulator }

    private let inset: NSSize

    private let regular = NSFont.monospacedSystemFont(ofSize: Theme.Size.terminal, weight: .regular)
    private lazy var bold = NSFont.monospacedSystemFont(ofSize: Theme.Size.terminal, weight: .bold)
    private lazy var italic: NSFont = {
        NSFont(descriptor: regular.fontDescriptor.withSymbolicTraits(.italic), size: Theme.Size.terminal) ?? regular
    }()
    private lazy var boldItalic: NSFont = {
        NSFont(descriptor: bold.fontDescriptor.withSymbolicTraits(.italic), size: Theme.Size.terminal) ?? bold
    }()

    /// What one cell measures: the advance of a monospaced character, and a
    /// line tall enough for the font's ascent and descent.
    private(set) lazy var cellSize: NSSize = {
        let advance = ("M" as NSString).size(withAttributes: [.font: regular]).width
        let height = ceil(CTFontGetAscent(regular) + CTFontGetDescent(regular) + CTFontGetLeading(regular))
        return NSSize(width: advance, height: height)
    }()

    /// Where a drag that is selecting began.
    private var anchor: (column: Int, row: Int)?
    private var pressedButton: MouseButton?

    /// A link the button went down on, and the cell it was in. Opened when the
    /// button comes up in the same cell.
    private struct PendingLink {
        var target: TerminalLink.Target
        var column: Int
        var row: Int
    }
    private var pendingLink: PendingLink?
    private var scrollRemainder: CGFloat = 0

    init(screen: TerminalScreen, inset: NSSize) {
        self.screen = screen
        self.inset = inset
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        screen.view = self
        // Pasteboard and drag: a file dropped on a terminal types its path.
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    // MARK: Layout

    override func layout() {
        super.layout()
        let columns = Int((bounds.width - 2 * inset.width) / cellSize.width)
        let rows = Int((bounds.height - 2 * inset.height) / cellSize.height)
        guard columns >= 2, rows >= 1 else { return }
        screen.resize(
            columns: columns, rows: rows,
            cellWidth: Int(cellSize.width), cellHeight: Int(cellSize.height)
        )
        needsDisplay = true
    }

    func invalidate(rows: Set<Int>) {
        guard !rows.isEmpty else { return }
        for row in rows { setNeedsDisplay(rect(forRow: row)) }
    }

    private func rect(forRow row: Int) -> NSRect {
        NSRect(
            x: 0, y: inset.height + CGFloat(row) * cellSize.height,
            width: bounds.width, height: cellSize.height
        )
    }

    private func cell(at point: NSPoint) -> (column: Int, row: Int) {
        let column = Int(((point.x - inset.width) / cellSize.width).rounded(.down))
        let row = Int(((point.y - inset.height) / cellSize.height).rounded(.down))
        return (max(0, min(column, emulator.columns - 1)), max(0, min(row, emulator.rows - 1)))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let cells = emulator.cells
        guard !cells.isEmpty else { return }

        // Clamped as numbers before they are rows: a layer-backed view can be
        // asked to draw an unbounded rect, which does not fit an `Int`.
        let top = ((dirtyRect.minY - inset.height) / cellSize.height).rounded(.down)
        let bottom = ((dirtyRect.maxY - inset.height) / cellSize.height).rounded(.down)
        let last = Int(min(max(bottom, 0), Double(cells.count - 1)))
        let first = Int(min(max(top, 0), Double(last)))
        guard bottom >= 0, top <= Double(cells.count - 1) else { return }

        for row in first...last {
            drawRow(row, cells[row], in: context)
        }
        if let cursor = emulator.cursor, (first...last).contains(cursor.row) {
            drawCursor(cursor, in: context)
        }
    }

    private func origin(column: Int, row: Int) -> NSPoint {
        NSPoint(x: inset.width + CGFloat(column) * cellSize.width, y: inset.height + CGFloat(row) * cellSize.height)
    }

    private func drawRow(_ row: Int, _ cells: [TerminalCell], in context: CGContext) {
        // Backgrounds first, in spans: neighbours that agree are one fill.
        var column = 0
        while column < cells.count {
            let background = fill(for: cells[column])
            var end = column + 1
            while end < cells.count, fill(for: cells[end]) == background { end += 1 }
            if let background {
                context.setFillColor(background.cgColor)
                let start = origin(column: column, row: row)
                context.fill(CGRect(x: start.x, y: start.y, width: CGFloat(end - column) * cellSize.width, height: cellSize.height))
            }
            column = end
        }

        // Then text, in runs that share a look. A run is drawn as one line of
        // text only when every character in it is one cell wide; anything else
        // is drawn where its cell is, so the grid never drifts.
        var runStart = 0
        var run = ""
        var runKey: RunKey?
        func flush() {
            guard let key = runKey, !run.isEmpty else { return }
            drawText(run, key: key, at: origin(column: runStart, row: row), in: context)
            run = ""
            runKey = nil
        }
        for (column, cell) in cells.enumerated() {
            if cell.text.isEmpty || cell.attributes.contains(.invisible) {
                // A gap ends a run, which keeps the next one at its own column.
                flush()
                continue
            }
            let key = RunKey(cell)
            let simple = cell.text.unicodeScalars.count == 1 && cell.text.unicodeScalars.first!.isASCII
            if !simple {
                flush()
                drawText(cell.text, key: key, at: origin(column: column, row: row), in: context)
                continue
            }
            if key != runKey { flush(); runKey = key; runStart = column }
            run += cell.text
        }
        flush()
    }

    private func fill(for cell: TerminalCell) -> NSColor? {
        if cell.isSelected { return Theme.Terminal.selection.nsColor }
        return cell.background?.nsColor
    }

    private struct RunKey: Equatable {
        var foreground: Theme.Terminal.RGB
        var attributes: TerminalCell.Attributes

        init(_ cell: TerminalCell) {
            foreground = cell.foreground
            attributes = cell.attributes
            // Links are always underlined, so they can be told from text.
            if cell.link != 0 { attributes.insert(.underline) }
        }
    }

    private func font(for attributes: TerminalCell.Attributes) -> NSFont {
        switch (attributes.contains(.bold), attributes.contains(.italic)) {
        case (true, true): boldItalic
        case (true, false): bold
        case (false, true): italic
        case (false, false): regular
        }
    }

    private func drawText(_ text: String, key: RunKey, at point: NSPoint, in context: CGContext) {
        var color = key.foreground.nsColor
        if key.attributes.contains(.faint) { color = color.withAlphaComponent(0.6) }
        if let block = BlockElement(text) {
            drawBlock(block, color: color, at: point, in: context)
            return
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: key.attributes),
            .foregroundColor: color,
        ]
        if key.attributes.contains(.underline) { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if key.attributes.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }

        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let ascent = CTFontGetAscent(regular)
        // The context is flipped to match the view, and Core Text draws
        // upright in an unflipped one: flip locally around the baseline.
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: point.x, y: point.y + ascent)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func drawBlock(_ block: BlockElement, color: NSColor, at point: NSPoint, in context: CGContext) {
        // Unsmoothed, so neighbouring blocks meet on a pixel instead of
        // leaving a faint seam where both edges are half covered.
        context.saveGState()
        context.setShouldAntialias(false)
        for part in block.parts {
            context.setFillColor(color.withAlphaComponent(color.alphaComponent * part.opacity).cgColor)
            context.fill(CGRect(
                x: point.x + part.rect.minX * cellSize.width, y: point.y + part.rect.minY * cellSize.height,
                width: part.rect.width * cellSize.width, height: part.rect.height * cellSize.height
            ))
        }
        context.restoreGState()
    }

    private func drawCursor(_ cursor: TerminalEmulator.Cursor, in context: CGContext) {
        let origin = origin(column: cursor.column, row: cursor.row)
        let color = Theme.Terminal.cursor.cgColor
        let focused = window?.firstResponder === self && window?.isKeyWindow == true
        context.setFillColor(color)
        context.setStrokeColor(color)
        switch (focused ? cursor.style : .hollow) {
        case .block:
            context.fill(CGRect(origin: origin, size: cellSize))
            // The character under it, in the colour of what it sits on.
            if cursor.row < emulator.cells.count, cursor.column < emulator.cells[cursor.row].count {
                let cell = emulator.cells[cursor.row][cursor.column]
                if !cell.text.isEmpty {
                    var key = RunKey(cell)
                    key.foreground = Theme.Terminal.background
                    drawText(cell.text, key: key, at: origin, in: context)
                }
            }
        case .hollow:
            context.stroke(CGRect(origin: origin, size: cellSize).insetBy(dx: 0.5, dy: 0.5))
        case .bar:
            context.fill(CGRect(x: origin.x, y: origin.y, width: 2, height: cellSize.height))
        case .underline:
            context.fill(CGRect(x: origin.x, y: origin.y + cellSize.height - 2, width: cellSize.width, height: 2))
        }
    }

    // MARK: Focus

    override func becomeFirstResponder() -> Bool {
        screen.isFocused = true
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        screen.isFocused = false
        needsDisplay = true
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.needsDisplay = true }
            }
        }
    }

    // MARK: Keyboard

    private func modifiers(of event: NSEvent) -> KeyModifiers {
        var result: KeyModifiers = []
        let flags = event.modifierFlags
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.capsLock) { result.insert(.capsLock) }
        return result
    }

    override func keyDown(with event: NSEvent) {
        // Command is the app's: Copy, Paste, tabs and the rest are menu items,
        // and a terminal has no use for the key a program could not tell from
        // them.
        if event.modifierFlags.contains(.command) { return }

        if let handler = screen.onKeyWhileEnded {
            handler()
            return
        }

        // Text the key makes, unless it is a control character or one of
        // AppKit's private-use codes for the function keys: the encoder knows
        // those by key. With Option as Alt the text is the key's, not the
        // accented character Option would make of it.
        let source = event.modifierFlags.contains(.option) ? event.charactersIgnoringModifiers : event.characters
        var text = source.flatMap { string -> String? in
            guard let scalar = string.unicodeScalars.first else { return nil }
            return scalar.value >= 0x20 && !(0xF700...0xF8FF).contains(scalar.value) && scalar.value != 0x7f ? string : nil
        }
        // Control and a letter has no text of its own: it is the key.
        if event.modifierFlags.contains(.control) { text = nil }
        let unshifted = event.charactersIgnoringModifiers?.unicodeScalars.first?.value ?? 0

        let bytes = emulator.encode(
            key: event.keyCode,
            action: event.isARepeat ? .repeating : .press,
            modifiers: modifiers(of: event),
            text: text,
            unshifted: unshifted
        )
        if bytes.isEmpty { return }
        emulator.clearSelection()
        // Return, and the keypad's Enter.
        screen.send(bytes, submits: [36, 76].contains(event.keyCode))
        screen.refresh()
    }

    // MARK: Clipboard

    @objc func copy(_ sender: Any?) {
        guard let text = screen.selectedText, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var clipboardPaste: ClipboardPaste? {
        let pasteboard = NSPasteboard.general
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return ClipboardPaste.choose(
            fileURLs: urls,
            text: pasteboard.string(forType: .string),
            hasImage: pasteboard.canReadObject(forClasses: [NSImage.self])
        )
    }

    @objc func paste(_ sender: Any?) {
        switch clipboardPaste {
        case .paths(let text), .text(let text): screen.paste(text)
        case .image: screen.pasteImage()
        case nil: break
        }
    }

    @objc override func selectAll(_ sender: Any?) {
        emulator.select(from: (0, 0), to: (emulator.columns - 1, emulator.rows - 1))
        screen.refresh()
    }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)): screen.selectedText?.isEmpty == false
        case #selector(paste(_:)): clipboardPaste != nil
        default: true
        }
    }

    // MARK: Mouse

    /// Whether the mouse belongs to the program: it asked for it, and Option
    /// is not held to say the person wants to select instead.
    private func programOwnsMouse(_ event: NSEvent) -> Bool {
        emulator.isTrackingMouse && !event.modifierFlags.contains(.option)
    }

    private func report(_ action: MouseAction, _ button: MouseButton?, _ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let bytes = emulator.encode(
            mouse: action, button: button, modifiers: modifiers(of: event),
            at: NSPoint(x: point.x - inset.width, y: point.y - inset.height),
            in: NSSize(width: bounds.width - 2 * inset.width, height: bounds.height - 2 * inset.height),
            cell: cellSize, scale: window?.backingScaleFactor ?? 2
        )
        screen.send(bytes)
    }

    /// The link under `point`, if the click it would be is a plain one: any
    /// modifier means something else is being asked for.
    private func link(at point: NSPoint, for event: NSEvent) -> PendingLink? {
        guard event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty else { return nil }
        let column = Int(((point.x - inset.width) / cellSize.width).rounded(.down))
        let row = Int(((point.y - inset.height) / cellSize.height).rounded(.down))
        // Not clamped, as `cell(at:)` is: the margin is not a link.
        guard let target = emulator.link(atColumn: column, row: row) else { return nil }
        return PendingLink(target: target, column: column, row: row)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        // A plain click on a link is the link's, and opens it when the button
        // comes up: after a drag it is a selection that started on a link.
        pendingLink = event.clickCount == 1 ? link(at: convert(event.locationInWindow, from: nil), for: event) : nil
        if pendingLink != nil, programOwnsMouse(event) { return }
        if programOwnsMouse(event) {
            pressedButton = .left
            report(.press, .left, event)
            return
        }
        let point = cell(at: convert(event.locationInWindow, from: nil))
        switch event.clickCount {
        case 1:
            anchor = point
            emulator.clearSelection()
        case 2:
            anchor = nil
            emulator.selectWord(column: point.column, row: point.row)
        default:
            anchor = nil
            emulator.selectLine(column: point.column, row: point.row)
        }
        screen.refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        if let pending = pendingLink {
            let point = cell(at: convert(event.locationInWindow, from: nil))
            if (point.column, point.row) != (pending.column, pending.row) { pendingLink = nil }
        }
        if pressedButton != nil, programOwnsMouse(event) {
            report(.motion, .left, event)
            return
        }
        guard let anchor else { return }
        let point = cell(at: convert(event.locationInWindow, from: nil))
        emulator.select(from: anchor, to: point, rectangle: event.modifierFlags.contains(.option) && event.modifierFlags.contains(.command))
        screen.refresh()
    }

    override func mouseUp(with event: NSEvent) {
        if let pending = pendingLink {
            pendingLink = nil
            let point = cell(at: convert(event.locationInWindow, from: nil))
            if (point.column, point.row) == (pending.column, pending.row) { screen.open(pending.target) }
        }
        if pressedButton != nil {
            pressedButton = nil
            if programOwnsMouse(event) { report(.release, .left, event) }
        }
        anchor = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        if programOwnsMouse(event) { report(.press, .right, event) } else { super.rightMouseDown(with: event) }
    }

    override func rightMouseUp(with event: NSEvent) {
        if programOwnsMouse(event) { report(.release, .right, event) } else { super.rightMouseUp(with: event) }
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: event)
        if programOwnsMouse(event) { report(.motion, nil, event) }
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(for: event)
    }

    /// A hand over what a click would open, as everywhere else.
    private func updateCursor(for event: NSEvent) {
        let overLink = link(at: convert(event.locationInWindow, from: nil), for: event) != nil
        (overLink ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    override func scrollWheel(with event: NSEvent) {
        // A trackpad reports points, a wheel reports lines; both become lines.
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / cellSize.height : event.scrollingDeltaY
        scrollRemainder += delta
        let lines = Int(scrollRemainder.rounded(.towardZero))
        guard lines != 0 else { return }
        scrollRemainder -= CGFloat(lines)

        if programOwnsMouse(event) {
            // Buttons four and five are the wheel, one press per line.
            for _ in 0..<abs(lines) { report(.press, lines > 0 ? .wheelUp : .wheelDown, event) }
            return
        }
        emulator.scroll(by: -lines)
        screen.refresh()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self
        ))
    }

    // MARK: Drops

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        screen.paste(ClipboardPaste.quoted(urls))
        return true
    }
}

private extension Theme.Terminal.RGB {
    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }

    var cgColor: CGColor { nsColor.cgColor }
}
