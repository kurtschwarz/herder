import Core
import DesignSystem
import Foundation
import GhosttyVt

/// A terminal screen: bytes in, a grid of cells out.
///
/// The one type that holds libghostty-vt's handles, and so the one that has to
/// change when its API does (rule 8). Nothing it exposes is a Ghostty type.
///
/// Not thread-safe: everything here is on the main actor, which is also where
/// the library calls its callbacks from, synchronously, inside ``write(_:)``.
final class TerminalEmulator {
    struct Cursor: Equatable {
        enum Style { case bar, block, underline, hollow }

        var column: Int
        var row: Int
        var style: Style
    }

    /// Where the viewport is in the scrollback: for a scroll bar, and to know
    /// whether it is at the bottom.
    struct Scroll: Equatable {
        var total: Int
        var offset: Int
        var visible: Int

        var isAtBottom: Bool { offset + visible >= total }
    }

    private(set) var columns: Int
    private(set) var rows: Int

    /// The screen, row by row. Only what ``update()`` last reported as changed
    /// has been rebuilt since the last call.
    private(set) var cells: [[TerminalCell]] = []
    private(set) var cursor: Cursor?

    /// What each row's cells can be clicked to open, indexed by
    /// ``TerminalCell/link`` less one. Per row, so a row rebuilt on its own
    /// has no table to keep in step with the rest.
    private var links: [[TerminalLink]] = []

    /// Whether each row carries on into the next, which makes the two one
    /// line of text as far as finding a link goes.
    private var wrapsToNextRow: [Bool] = []

    /// Where a relative path is taken from: the shell's directory, as it last
    /// said, else where it started.
    var workingDirectory: URL?

    var homeDirectory = FileManager.default.homeDirectoryForCurrentUser

    /// A path is a link only if something is there. Replaced by tests.
    var fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }

    /// What the terminal answers back to the program: a device-attributes
    /// reply, a cursor-position report. Goes to the pty.
    var onReply: ((Data) -> Void)?
    var onBell: (() -> Void)?

    /// A program put text on the clipboard (OSC 52). Reads are refused: the
    /// callback for them is never installed.
    var onClipboardWrite: ((String) -> Void)?

    /// A shell said where it is (OSC 7), or `nil` when it said nothing usable.
    var onWorkingDirectory: ((URL?) -> Void)?

    /// The program named itself (OSC 0 or 2). Empty when it cleared the name.
    var onTitle: ((String) -> Void)?

    /// What a program status report (OSC 7501) asks of the records kept for
    /// it. The library checks and decodes the report, and keeps nothing.
    enum ProgramStatusReport: Equatable {
        /// Replace the record with this one's id.
        case put(ProgramStatus)
        /// Remove the record with this id and every record beneath it.
        case clear(String)
    }

    /// The program reported its status (OSC 7501). Also called with a clear of
    /// everything on a full reset.
    var onProgramStatus: ((ProgramStatusReport) -> Void)?

    // CONCURRENCY: C handles, which are not `Sendable`. They are made in `init`
    // and used only on the main actor; `nonisolated(unsafe)` is for `deinit`,
    // which is not isolated and is the last thing to touch them.
    private nonisolated(unsafe) var terminal: GhosttyTerminal
    private nonisolated(unsafe) var renderState: GhosttyRenderState
    private nonisolated(unsafe) var rowIterator: GhosttyRenderStateRowIterator
    private nonisolated(unsafe) var rowCells: GhosttyRenderStateRowCells
    private nonisolated(unsafe) var keyEncoder: GhosttyKeyEncoder
    private nonisolated(unsafe) var keyEvent: GhosttyKeyEvent
    private nonisolated(unsafe) var mouseEncoder: GhosttyMouseEncoder
    private nonisolated(unsafe) var mouseEvent: GhosttyMouseEvent

    /// Set when a resize or reset means the next ``update()`` has to rebuild
    /// every row, whatever the library says is dirty.
    private var needsFullRebuild = true

    init(columns: Int, rows: Int, scrollbackLines: Int) {
        self.columns = columns
        self.rows = rows

        var terminal: GhosttyTerminal?
        precondition(ghostty_terminal_new(nil, &terminal, UInt16(columns), UInt16(rows)) == GHOSTTY_SUCCESS)
        self.terminal = terminal!
        var renderState: GhosttyRenderState?
        precondition(ghostty_render_state_new(nil, &renderState) == GHOSTTY_SUCCESS)
        self.renderState = renderState!
        var rowIterator: GhosttyRenderStateRowIterator?
        precondition(ghostty_render_state_row_iterator_new(nil, &rowIterator) == GHOSTTY_SUCCESS)
        self.rowIterator = rowIterator!
        var rowCells: GhosttyRenderStateRowCells?
        precondition(ghostty_render_state_row_cells_new(nil, &rowCells) == GHOSTTY_SUCCESS)
        self.rowCells = rowCells!
        var keyEncoder: GhosttyKeyEncoder?
        precondition(ghostty_key_encoder_new(nil, &keyEncoder) == GHOSTTY_SUCCESS)
        self.keyEncoder = keyEncoder!
        var keyEvent: GhosttyKeyEvent?
        precondition(ghostty_key_event_new(nil, &keyEvent) == GHOSTTY_SUCCESS)
        self.keyEvent = keyEvent!
        var mouseEncoder: GhosttyMouseEncoder?
        precondition(ghostty_mouse_encoder_new(nil, &mouseEncoder) == GHOSTTY_SUCCESS)
        self.mouseEncoder = mouseEncoder!
        var mouseEvent: GhosttyMouseEvent?
        precondition(ghostty_mouse_event_new(nil, &mouseEvent) == GHOSTTY_SUCCESS)
        self.mouseEvent = mouseEvent!

        configure(scrollbackLines: scrollbackLines)
    }

    deinit {
        ghostty_mouse_event_free(mouseEvent)
        ghostty_mouse_encoder_free(mouseEncoder)
        ghostty_key_event_free(keyEvent)
        ghostty_key_encoder_free(keyEncoder)
        ghostty_render_state_row_cells_free(rowCells)
        ghostty_render_state_row_iterator_free(rowIterator)
        ghostty_render_state_free(renderState)
        ghostty_terminal_free(terminal)
    }

    // MARK: Setup

    private func configure(scrollbackLines: Int) {
        // The value is the pointer itself, as it is for the callbacks below,
        // and not a pointer to it.
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_USERDATA, Unmanaged.passUnretained(self).toOpaque())

        var lines = scrollbackLines
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_LINES, &lines)

        var foreground = rgb(Theme.Terminal.foreground)
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND, &foreground)
        var background = rgb(Theme.Terminal.background)
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND, &background)
        var cursorColor = rgb(Theme.Terminal.cursor)
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_COLOR_CURSOR, &cursorColor)
        var palette = Self.palette()
        palette.withUnsafeMutableBufferPointer {
            _ = ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_COLOR_PALETTE, $0.baseAddress)
        }

        // The callbacks are C function pointers, so they cannot capture; they
        // find the emulator through the userdata above. They are called inside
        // `ghostty_terminal_vt_write`, which is called on the main actor.
        let writePty: GhosttyTerminalWritePtyFn = { _, userdata, bytes, length in
            guard let userdata, let bytes else { return }
            let data = Data(bytes: bytes, count: length)
            MainActor.assumeIsolated {
                Unmanaged<TerminalEmulator>.fromOpaque(userdata).takeUnretainedValue().onReply?(data)
            }
        }
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_WRITE_PTY, unsafeBitCast(writePty, to: UnsafeRawPointer.self))

        let bell: GhosttyTerminalBellFn = { _, userdata in
            guard let userdata else { return }
            MainActor.assumeIsolated {
                Unmanaged<TerminalEmulator>.fromOpaque(userdata).takeUnretainedValue().onBell?()
            }
        }
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_BELL, unsafeBitCast(bell, to: UnsafeRawPointer.self))

        let pwd: GhosttyTerminalPwdChangedFn = { _, userdata in
            guard let userdata else { return }
            MainActor.assumeIsolated {
                let emulator = Unmanaged<TerminalEmulator>.fromOpaque(userdata).takeUnretainedValue()
                emulator.onWorkingDirectory?(emulator.reportedWorkingDirectory())
            }
        }
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_PWD_CHANGED, unsafeBitCast(pwd, to: UnsafeRawPointer.self))

        let title: GhosttyTerminalTitleChangedFn = { _, userdata in
            guard let userdata else { return }
            MainActor.assumeIsolated {
                let emulator = Unmanaged<TerminalEmulator>.fromOpaque(userdata).takeUnretainedValue()
                emulator.onTitle?(emulator.reportedTitle())
            }
        }
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_TITLE_CHANGED, unsafeBitCast(title, to: UnsafeRawPointer.self))

        // Installing it is also what makes the library answer a program that
        // asks whether reports are understood (OSC 7501 ; ?), through
        // `writePty` above.
        let programStatus: GhosttyTerminalProgramStatusFn = { _, userdata, report in
            guard let userdata, let report else { return }
            let parsed = TerminalEmulator.programStatus(report.pointee)
            MainActor.assumeIsolated {
                Unmanaged<TerminalEmulator>.fromOpaque(userdata).takeUnretainedValue().onProgramStatus?(parsed)
            }
        }
        ghostty_terminal_set(
            terminal, GHOSTTY_TERMINAL_OPT_PROGRAM_STATUS, unsafeBitCast(programStatus, to: UnsafeRawPointer.self)
        )

        let clipboard: GhosttyTerminalClipboardWriteFn = { _, userdata, write in
            guard let userdata, let write else { return }
            // Text only, and only the first representation that is text.
            var text: String?
            for index in 0..<write.pointee.contents_len {
                let content = write.pointee.contents[index]
                let mime = content.mime.len == 0
                    ? "text/plain"
                    : String(decoding: UnsafeBufferPointer(start: content.mime.ptr, count: content.mime.len), as: UTF8.self)
                if mime.hasPrefix("text/"), let pointer = content.data.ptr {
                    text = String(decoding: UnsafeBufferPointer(start: pointer, count: content.data.len), as: UTF8.self)
                    break
                }
            }
            var reply = GhosttyClipboardWriteReply(size: MemoryLayout<GhosttyClipboardWriteReply>.size, result: GHOSTTY_CLIPBOARD_WRITE_RESULT_UNSUPPORTED, remember: false)
            if let text {
                MainActor.assumeIsolated {
                    Unmanaged<TerminalEmulator>.fromOpaque(userdata).takeUnretainedValue().onClipboardWrite?(text)
                }
                reply.result = GHOSTTY_CLIPBOARD_WRITE_RESULT_SUCCESS
            }
            write.pointee.reply?(write, &reply)
        }
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_CLIPBOARD_WRITE, unsafeBitCast(clipboard, to: UnsafeRawPointer.self))

        // What the child is told about itself. Matches what the shell was
        // launched with, so a program that asks gets the same answer twice.
        var optionAsAlt = GHOSTTY_OPTION_AS_ALT_TRUE
        ghostty_key_encoder_setopt(keyEncoder, GHOSTTY_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT, &optionAsAlt)
    }

    private func rgb(_ color: Theme.Terminal.RGB) -> GhosttyColorRgb {
        GhosttyColorRgb(r: color.red, g: color.green, b: color.blue)
    }

    /// The 256 colours: the theme's sixteen, then the cube and the greys,
    /// which are what every terminal agrees they are and so are not themed.
    private static func palette() -> [GhosttyColorRgb] {
        var palette = Theme.Terminal.ansi.map { GhosttyColorRgb(r: $0.red, g: $0.green, b: $0.blue) }
        let levels: [UInt8] = [0, 95, 135, 175, 215, 255]
        for index in 16..<232 {
            let n = index - 16
            palette.append(GhosttyColorRgb(r: levels[n / 36], g: levels[n / 6 % 6], b: levels[n % 6]))
        }
        for index in 232..<256 {
            let level = UInt8(8 + (index - 232) * 10)
            palette.append(GhosttyColorRgb(r: level, g: level, b: level))
        }
        return palette
    }

    // MARK: Output

    /// Feeds the terminal what the process wrote.
    func write(_ data: Data) {
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            ghostty_terminal_vt_write(terminal, base, raw.count)
        }
    }

    func resize(columns: Int, rows: Int, cellWidth: Int, cellHeight: Int) {
        guard columns > 0, rows > 0 else { return }
        self.columns = columns
        self.rows = rows
        ghostty_terminal_resize(terminal, UInt16(columns), UInt16(rows), UInt32(cellWidth), UInt32(cellHeight))
        needsFullRebuild = true
    }

    /// Brings ``cells`` and ``cursor`` up to date, and says which rows changed.
    @discardableResult
    func update() -> Set<Int> {
        guard ghostty_render_state_update(renderState, terminal) == GHOSTTY_SUCCESS else { return [] }

        var dirty = GHOSTTY_RENDER_STATE_DIRTY_FALSE
        ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_DIRTY, &dirty)

        var colors = GhosttyRenderStateColors()
        colors.size = MemoryLayout<GhosttyRenderStateColors>.size
        ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_COLORS, &colors)

        let rebuildAll = needsFullRebuild || cells.count != rows
        if rebuildAll {
            cells = Array(repeating: Array(repeating: TerminalCell(), count: columns), count: rows)
            links = Array(repeating: [], count: rows)
            wrapsToNextRow = Array(repeating: false, count: rows)
            needsFullRebuild = false
        }

        var changed: Set<Int> = []
        if dirty != GHOSTTY_RENDER_STATE_DIRTY_FALSE || rebuildAll {
            ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, &rowIterator)
            if rebuildAll {
                // Every row, not only the ones the library flags: after a
                // resize it flags what moved, and the array is new.
                var row = 0
                while ghostty_render_state_row_iterator_next(rowIterator) {
                    readRow(row, colors: colors)
                    changed.insert(row)
                    row += 1
                }
            } else {
                var row: UInt16 = 0
                while ghostty_render_state_row_iterator_next_dirty(rowIterator, &row) {
                    readRow(Int(row), colors: colors)
                    changed.insert(Int(row))
                }
            }
        }

        // Links found in the text, which can run over several rows, so a row
        // that did not change can still need drawing again.
        changed.formUnion(detectLinks(in: changed))

        let newCursor = readCursor()
        if newCursor != cursor {
            // The old and the new cell both need drawing.
            if let old = cursor { changed.insert(old.row) }
            if let new = newCursor { changed.insert(new.row) }
            cursor = newCursor
        }

        ghostty_render_state_clean(renderState)
        return changed.filter { $0 < rows }
    }

    private func readRow(_ y: Int, colors: GhosttyRenderStateColors) {
        guard y < cells.count else { return }
        guard ghostty_render_state_row_get(rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, &rowCells) == GHOSTTY_SUCCESS else {
            return
        }

        // Only a row the library says has a hyperlink is asked about each
        // cell's, which is a call per cell.
        var rawRow: GhosttyRow = 0
        var wraps = false
        var hasHyperlink = false
        if ghostty_render_state_row_get(rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_RAW, &rawRow) == GHOSTTY_SUCCESS {
            ghostty_row_get(rawRow, GHOSTTY_ROW_DATA_WRAP, &wraps)
            ghostty_row_get(rawRow, GHOSTTY_ROW_DATA_HYPERLINK, &hasHyperlink)
        }
        wrapsToNextRow[y] = wraps
        links[y] = []

        var x = 0
        while ghostty_render_state_row_cells_next(rowCells), x < columns {
            defer { x += 1 }
            var cell = TerminalCell()

            var length: UInt32 = 0
            ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN, &length)
            if length > 0 {
                var codepoints = [UInt32](repeating: 0, count: Int(length))
                ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF, &codepoints)
                var text = String.UnicodeScalarView()
                for codepoint in codepoints { if let scalar = Unicode.Scalar(codepoint) { text.append(scalar) } }
                cell.text = String(text)
            }

            var style = GhosttyStyle()
            style.size = MemoryLayout<GhosttyStyle>.size
            ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE, &style)

            var color = GhosttyColorRgb()
            var foreground: Theme.Terminal.RGB?
            var background: Theme.Terminal.RGB?
            if ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_FG_COLOR, &color) == GHOSTTY_SUCCESS {
                foreground = Self.theme(color)
            }
            if ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR, &color) == GHOSTTY_SUCCESS {
                background = Self.theme(color)
            }

            // Inverse swaps the two, and the terminal's own colours count: an
            // inverse cell with no colours of its own is the foreground as a
            // block with the background as its text.
            if style.inverse {
                let swapped = (foreground ?? Theme.Terminal.foreground, background ?? Theme.Terminal.background)
                (foreground, background) = (swapped.1, swapped.0)
            }
            cell.foreground = foreground ?? Theme.Terminal.foreground
            cell.background = background

            if style.bold { cell.attributes.insert(.bold) }
            if style.italic { cell.attributes.insert(.italic) }
            if style.faint { cell.attributes.insert(.faint) }
            if style.underline != 0 { cell.attributes.insert(.underline) }
            if style.strikethrough { cell.attributes.insert(.strikethrough) }
            if style.invisible { cell.attributes.insert(.invisible) }

            var selected = false
            ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_SELECTED, &selected)
            cell.isSelected = selected

            if hasHyperlink {
                var rawCell: GhosttyCell = 0
                var linked = false
                if ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW, &rawCell) == GHOSTTY_SUCCESS {
                    ghostty_cell_get(rawCell, GHOSTTY_CELL_DATA_HAS_HYPERLINK, &linked)
                }
                if linked, let target = hyperlinkTarget(column: x, row: y) {
                    cell.link = linkID(for: TerminalLink(target: target, isDetected: false), inRow: y)
                }
            }

            cells[y][x] = cell
        }
    }

    // MARK: Links

    /// What a click on this cell opens, if anything.
    func link(atColumn column: Int, row: Int) -> TerminalLink.Target? {
        guard cells.indices.contains(row), cells[row].indices.contains(column) else { return nil }
        let id = cells[row][column].link
        guard id > 0, links[row].indices.contains(id - 1) else { return nil }
        return links[row][id - 1].target
    }

    /// The URI a program marked this cell with (OSC 8), as something to open.
    private func hyperlinkTarget(column: Int, row: Int) -> TerminalLink.Target? {
        guard var reference = reference(column: column, row: row) else { return nil }
        var length = 0
        _ = ghostty_grid_ref_hyperlink_uri(&reference, nil, 0, &length)
        guard length > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: length)
        guard ghostty_grid_ref_hyperlink_uri(&reference, &bytes, length, &length) == GHOSTTY_SUCCESS else { return nil }
        guard let url = URL(string: String(decoding: bytes.prefix(length), as: UTF8.self)) else { return nil }
        // `file://host/path`, as `ls --hyperlink` writes it, is a file here.
        return url.isFileURL ? .file(URL(filePath: url.path(percentEncoded: false)), line: nil, column: nil) : .url(url)
    }

    private func linkID(for link: TerminalLink, inRow row: Int) -> Int {
        if let index = links[row].firstIndex(of: link) { return index + 1 }
        links[row].append(link)
        return links[row].count
    }

    /// Finds the links in the text of every line that has a row in `rows`,
    /// and returns the rows whose links are not what they were.
    ///
    /// Done when rows are read, not when they are drawn. A line is the rows
    /// that wrap into one another, so a URL that runs onto the next row is one
    /// link.
    private func detectLinks(in rows: Set<Int>) -> Set<Int> {
        var changed: Set<Int> = []
        var done: Set<Int> = []
        for row in rows.sorted() where row < cells.count && !done.contains(row) {
            var first = row
            while first > 0, wrapsToNextRow[first - 1] { first -= 1 }
            var last = row
            while last < cells.count - 1, wrapsToNextRow[last] { last += 1 }
            done.formUnion(first...last)
            changed.formUnion(detectLinks(inRows: first...last))
        }
        return changed
    }

    private func detectLinks(inRows lines: ClosedRange<Int>) -> Set<Int> {
        let before = lines.map { (cells[$0].map(\.link), links[$0]) }
        for row in lines { dropDetectedLinks(inRow: row) }

        // One string for the line, and which cell each of its UTF-16 units
        // came from. A blank cell is a space, so words stay apart.
        var text = ""
        var cellOfUnit: [(row: Int, column: Int)] = []
        for row in lines {
            for (column, cell) in cells[row].enumerated() {
                let character = cell.text.isEmpty ? " " : cell.text
                text += character
                cellOfUnit.append(contentsOf: repeatElement((row: row, column: column), count: character.utf16.count))
            }
        }

        // Nearly every line has neither, and none of the three kinds of link
        // can be without one of them.
        if text.contains(where: { $0 == "/" || $0 == ":" }) {
            for candidate in TerminalLinkDetector.candidates(in: text) {
                // What the program marked is left as it is: only that is
                // still set, as the detected links were dropped above.
                guard !candidate.range.contains(where: { cells[cellOfUnit[$0].row][cellOfUnit[$0].column].link != 0 }),
                      let target = target(for: candidate.kind)
                else { continue }
                var ids: [Int: Int] = [:]
                for unit in candidate.range {
                    let (row, column) = cellOfUnit[unit]
                    let id = ids[row] ?? linkID(for: TerminalLink(target: target, isDetected: true), inRow: row)
                    ids[row] = id
                    cells[row][column].link = id
                }
            }
        }

        var changed: Set<Int> = []
        for (index, row) in lines.enumerated() where before[index] != (cells[row].map(\.link), links[row]) {
            changed.insert(row)
        }
        return changed
    }

    /// Throws away what was found in a row's text, keeping what the program
    /// marked, so the line can be looked at again.
    private func dropDetectedLinks(inRow row: Int) {
        guard links[row].contains(where: \.isDetected) else { return }
        var kept: [TerminalLink] = []
        var renumbered: [Int: Int] = [:]
        for (index, link) in links[row].enumerated() where !link.isDetected {
            kept.append(link)
            renumbered[index + 1] = kept.count
        }
        for column in cells[row].indices where cells[row][column].link != 0 {
            cells[row][column].link = renumbered[cells[row][column].link] ?? 0
        }
        links[row] = kept
    }

    private func target(for kind: TerminalLinkCandidate.Kind) -> TerminalLink.Target? {
        switch kind {
        case .url(let url):
            return .url(url)
        case .path(let reference):
            guard let url = reference.resolved(against: workingDirectory, home: homeDirectory), fileExists(url) else {
                return nil
            }
            return .file(url, line: reference.line, column: reference.column)
        }
    }

    private static func theme(_ color: GhosttyColorRgb) -> Theme.Terminal.RGB {
        Theme.Terminal.RGB(UInt32(color.r) << 16 | UInt32(color.g) << 8 | UInt32(color.b))
    }

    private func readCursor() -> Cursor? {
        var cursor = GhosttyRenderStateCursor()
        cursor.size = MemoryLayout<GhosttyRenderStateCursor>.size
        guard ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR, &cursor) == GHOSTTY_SUCCESS,
              cursor.visible, cursor.viewport_has_value
        else { return nil }
        let style: Cursor.Style = switch cursor.visual_style {
        case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR: .bar
        case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_UNDERLINE: .underline
        case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK_HOLLOW: .hollow
        default: .block
        }
        return Cursor(column: Int(cursor.viewport_x), row: Int(cursor.viewport_y), style: style)
    }

    private func reportedTitle() -> String {
        var string = GhosttyString()
        guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_TITLE, &string) == GHOSTTY_SUCCESS else { return "" }
        return Self.text(string)
    }

    /// A borrowed string, copied out before the library can change it.
    private nonisolated static func text(_ string: GhosttyString) -> String {
        guard string.len > 0, let pointer = string.ptr else { return "" }
        return String(decoding: UnsafeBufferPointer(start: pointer, count: string.len), as: UTF8.self)
    }

    /// A report, copied out of the library's memory. Its text is shown
    /// outside the terminal, so invisible formatting such as a direction
    /// override is taken out of it.
    private nonisolated static func programStatus(_ report: GhosttyTerminalProgramStatus) -> ProgramStatusReport {
        let id = text(report.id)
        let state: ProgramStatus.State
        switch report.state {
        case GHOSTTY_PROGRAM_STATUS_STATE_CLEAR: return .clear(id)
        case GHOSTTY_PROGRAM_STATUS_STATE_WORKING: state = .working
        case GHOSTTY_PROGRAM_STATUS_STATE_DONE: state = .done
        case GHOSTTY_PROGRAM_STATUS_STATE_BLOCKED: state = .blocked
        case GHOSTTY_PROGRAM_STATUS_STATE_ERROR: state = .error
        default: state = .idle
        }
        let need: ProgramStatus.Need? = switch report.kind {
        case GHOSTTY_PROGRAM_STATUS_KIND_PERMISSION: .permission
        case GHOSTTY_PROGRAM_STATUS_KIND_QUESTION: .question
        case GHOSTTY_PROGRAM_STATUS_KIND_AUTH: .auth
        default: nil
        }
        return .put(ProgramStatus(
            id: id,
            state: state,
            need: need,
            progress: report.progress < 0 ? nil : Int(report.progress),
            app: text(report.app),
            title: visible(text(report.title)),
            message: visible(text(report.message))
        ))
    }

    /// Without format characters, but for the joiners, which emoji are made
    /// with.
    private nonisolated static func visible(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.filter {
            $0.properties.generalCategory != .format || $0.value == 0x200C || $0.value == 0x200D
        })
        return String(scalars)
    }

    private func reportedWorkingDirectory() -> URL? {
        var string = GhosttyString()
        guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_PWD, &string) == GHOSTTY_SUCCESS,
              string.len > 0, let pointer = string.ptr
        else { return nil }
        let text = String(decoding: UnsafeBufferPointer(start: pointer, count: string.len), as: UTF8.self)
        // `file://host/path` is what OSC 7 carries; a bare path is tolerated.
        if let url = URL(string: text), url.isFileURL { return url }
        return text.hasPrefix("/") ? URL(filePath: text, directoryHint: .isDirectory) : nil
    }

    // MARK: Scrollback

    var scroll: Scroll {
        var scrollbar = GhosttyTerminalScrollbar()
        ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_SCROLLBAR, &scrollbar)
        return Scroll(total: Int(scrollbar.total), offset: Int(scrollbar.offset), visible: Int(scrollbar.len))
    }

    /// Moves the viewport by `lines`: negative is up, into history.
    func scroll(by lines: Int) {
        var behavior = GhosttyTerminalScrollViewport()
        behavior.tag = GHOSTTY_SCROLL_VIEWPORT_DELTA
        behavior.value.delta = lines
        ghostty_terminal_scroll_viewport(terminal, behavior)
    }

    func scrollToBottom() {
        var behavior = GhosttyTerminalScrollViewport()
        behavior.tag = GHOSTTY_SCROLL_VIEWPORT_BOTTOM
        ghostty_terminal_scroll_viewport(terminal, behavior)
    }

    // MARK: Modes

    /// A program has asked to be told about the mouse (vim, htop, tmux).
    var isTrackingMouse: Bool {
        var tracking = false
        ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_MOUSE_TRACKING, &tracking)
        return tracking
    }

    var isOnAlternateScreen: Bool {
        var screen = GHOSTTY_TERMINAL_SCREEN_PRIMARY
        ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN, &screen)
        return screen == GHOSTTY_TERMINAL_SCREEN_ALTERNATE
    }

    private func isEnabled(_ mode: GhosttyMode) -> Bool {
        var config = GhosttyTerminalModeConfig(mode: mode, value: false)
        ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_MODE, &config)
        return config.value
    }

    // MARK: Selection

    private func reference(column: Int, row: Int) -> GhosttyGridRef? {
        var reference = GhosttyGridRef()
        reference.size = MemoryLayout<GhosttyGridRef>.size
        let point = GhosttyPoint(
            tag: GHOSTTY_POINT_TAG_VIEWPORT,
            value: GhosttyPointValue(coordinate: GhosttyPointCoordinate(
                x: UInt16(clamping: max(0, min(column, columns - 1))),
                y: UInt32(max(0, min(row, rows - 1)))
            ))
        )
        return ghostty_terminal_grid_ref(terminal, point, &reference) == GHOSTTY_SUCCESS ? reference : nil
    }

    private func apply(_ selection: GhosttySelection?) {
        if var selection {
            ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_SELECTION, &selection)
        } else {
            ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_SELECTION, nil)
        }
    }

    /// Selects the cells from one point to another, in screen coordinates.
    func select(from start: (column: Int, row: Int), to end: (column: Int, row: Int), rectangle: Bool = false) {
        guard let from = reference(column: start.column, row: start.row),
              let to = reference(column: end.column, row: end.row)
        else { return }
        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        selection.start = from
        selection.end = to
        selection.rectangle = rectangle
        apply(selection)
    }

    func selectWord(column: Int, row: Int) {
        guard let reference = reference(column: column, row: row) else { return }
        var options = GhosttyTerminalSelectWordOptions()
        options.size = MemoryLayout<GhosttyTerminalSelectWordOptions>.size
        options.ref = reference
        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        if ghostty_terminal_select_word(terminal, &options, &selection) == GHOSTTY_SUCCESS { apply(selection) }
    }

    func selectLine(column: Int, row: Int) {
        guard let reference = reference(column: column, row: row) else { return }
        var options = GhosttyTerminalSelectLineOptions()
        options.size = MemoryLayout<GhosttyTerminalSelectLineOptions>.size
        options.ref = reference
        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        if ghostty_terminal_select_line(terminal, &options, &selection) == GHOSTTY_SUCCESS { apply(selection) }
    }

    func clearSelection() {
        apply(nil)
    }

    /// What is selected, as text: wrapped lines joined, trailing blanks gone.
    /// `nil` when nothing is.
    var selectedText: String? {
        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_SELECTION, &selection) == GHOSTTY_SUCCESS else {
            return nil
        }
        return withUnsafePointer(to: &selection) { pointer -> String? in
            var options = GhosttyTerminalSelectionFormatOptions()
            options.size = MemoryLayout<GhosttyTerminalSelectionFormatOptions>.size
            options.emit = GHOSTTY_FORMATTER_FORMAT_PLAIN
            options.unwrap = true
            options.trim = true
            options.selection = pointer
            var buffer: UnsafeMutablePointer<UInt8>?
            var length = 0
            guard ghostty_terminal_selection_format_alloc(terminal, nil, options, &buffer, &length) == GHOSTTY_SUCCESS,
                  let buffer
            else { return nil }
            defer { ghostty_free(nil, buffer, length) }
            return String(decoding: UnsafeBufferPointer(start: buffer, count: length), as: UTF8.self)
        }
    }

    // MARK: Input

    /// What to send for a key, or empty when the terminal has nothing to say
    /// for it. Reads the modes (cursor keys, keypad, kitty) off the terminal
    /// each time, so a program that switches them is obeyed from the next key.
    func encode(
        key: UInt16,
        action: KeyAction,
        modifiers: KeyModifiers,
        text: String?,
        unshifted: UInt32
    ) -> Data {
        guard let mapped = KeyMap.key(forKeyCode: key) else { return Data() }
        ghostty_key_encoder_setopt_from_terminal(keyEncoder, terminal)
        // `setopt_from_terminal` takes the option-as-alt default; ours is set
        // after it, and again here, because it is the user's choice, not the
        // program's.
        var optionAsAlt = GHOSTTY_OPTION_AS_ALT_TRUE
        ghostty_key_encoder_setopt(keyEncoder, GHOSTTY_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT, &optionAsAlt)

        ghostty_key_event_set_action(keyEvent, action.ghostty)
        ghostty_key_event_set_key(keyEvent, mapped)
        ghostty_key_event_set_mods(keyEvent, modifiers.ghostty)
        ghostty_key_event_set_consumed_mods(keyEvent, text == nil ? 0 : GhosttyMods(GHOSTTY_MODS_SHIFT))
        ghostty_key_event_set_unshifted_codepoint(keyEvent, unshifted)

        var buffer = [CChar](repeating: 0, count: 128)
        var written = 0
        let result: GhosttyResult
        if let text, !text.isEmpty {
            result = text.withCString { pointer in
                ghostty_key_event_set_utf8(keyEvent, pointer, strlen(pointer))
                return ghostty_key_encoder_encode(keyEncoder, keyEvent, &buffer, buffer.count, &written)
            }
        } else {
            ghostty_key_event_set_utf8(keyEvent, nil, 0)
            result = ghostty_key_encoder_encode(keyEncoder, keyEvent, &buffer, buffer.count, &written)
        }
        guard result == GHOSTTY_SUCCESS else { return Data() }
        return Data(buffer.prefix(written).map { UInt8(bitPattern: $0) })
    }

    /// What to send for pasted text: as typed, or between the bracketed-paste
    /// markers when the program asked for them.
    func encodePaste(_ text: String) -> Data {
        var bytes = Array(text.utf8CString.dropLast())
        // A newline typed into a terminal is a carriage return.
        for index in bytes.indices where bytes[index] == 0x0a { bytes[index] = 0x0d }
        let bracketed = isEnabled(ghostty_mode_new(2004, false))
        var output = [CChar](repeating: 0, count: bytes.count + 16)
        var written = 0
        guard ghostty_paste_encode(&bytes, bytes.count, bracketed, &output, output.count, &written) == GHOSTTY_SUCCESS else {
            return Data()
        }
        return Data(output.prefix(written).map { UInt8(bitPattern: $0) })
    }

    /// What to send a program that is tracking the mouse, for something the
    /// mouse did at `point` (in view points, from the top left). Empty when
    /// the terminal's modes say the program does not want it.
    func encode(
        mouse action: MouseAction,
        button: MouseButton?,
        modifiers: KeyModifiers,
        at point: CGPoint,
        in size: CGSize,
        cell: CGSize,
        scale: CGFloat
    ) -> Data {
        ghostty_mouse_encoder_setopt_from_terminal(mouseEncoder, terminal)
        var geometry = GhosttyMouseEncoderSize()
        geometry.size = MemoryLayout<GhosttyMouseEncoderSize>.size
        geometry.screen_width = UInt32(size.width * scale)
        geometry.screen_height = UInt32(size.height * scale)
        geometry.cell_width = UInt32(cell.width * scale)
        geometry.cell_height = UInt32(cell.height * scale)
        ghostty_mouse_encoder_setopt(mouseEncoder, GHOSTTY_MOUSE_ENCODER_OPT_SIZE, &geometry)
        var pressed = button != nil && action != .release
        ghostty_mouse_encoder_setopt(mouseEncoder, GHOSTTY_MOUSE_ENCODER_OPT_ANY_BUTTON_PRESSED, &pressed)

        ghostty_mouse_event_set_action(mouseEvent, action.ghostty)
        if let button { ghostty_mouse_event_set_button(mouseEvent, button.ghostty) } else { ghostty_mouse_event_clear_button(mouseEvent) }
        ghostty_mouse_event_set_mods(mouseEvent, modifiers.ghostty)
        ghostty_mouse_event_set_position(mouseEvent, GhosttyMousePosition(x: Float(point.x * scale), y: Float(point.y * scale)))

        var buffer = [CChar](repeating: 0, count: 64)
        var written = 0
        guard ghostty_mouse_encoder_encode(mouseEncoder, mouseEvent, &buffer, buffer.count, &written) == GHOSTTY_SUCCESS else {
            return Data()
        }
        return Data(buffer.prefix(written).map { UInt8(bitPattern: $0) })
    }
}

// MARK: Input vocabulary

/// Here so nothing that sends a key has to name a Ghostty enum.
enum KeyAction {
    case press, repeating, release

    var ghostty: GhosttyKeyAction {
        switch self {
        case .press: GHOSTTY_KEY_ACTION_PRESS
        case .repeating: GHOSTTY_KEY_ACTION_REPEAT
        case .release: GHOSTTY_KEY_ACTION_RELEASE
        }
    }
}

struct KeyModifiers: OptionSet {
    let rawValue: UInt16

    static let shift = KeyModifiers(rawValue: 1 << 0)
    static let control = KeyModifiers(rawValue: 1 << 1)
    static let option = KeyModifiers(rawValue: 1 << 2)
    static let command = KeyModifiers(rawValue: 1 << 3)
    static let capsLock = KeyModifiers(rawValue: 1 << 4)

    var ghostty: GhosttyMods {
        var mods: GhosttyMods = 0
        if contains(.shift) { mods |= GhosttyMods(GHOSTTY_MODS_SHIFT) }
        if contains(.control) { mods |= GhosttyMods(GHOSTTY_MODS_CTRL) }
        if contains(.option) { mods |= GhosttyMods(GHOSTTY_MODS_ALT) }
        if contains(.command) { mods |= GhosttyMods(GHOSTTY_MODS_SUPER) }
        if contains(.capsLock) { mods |= GhosttyMods(GHOSTTY_MODS_CAPS_LOCK) }
        return mods
    }
}

enum MouseAction {
    case press, release, motion

    var ghostty: GhosttyMouseAction {
        switch self {
        case .press: GHOSTTY_MOUSE_ACTION_PRESS
        case .release: GHOSTTY_MOUSE_ACTION_RELEASE
        case .motion: GHOSTTY_MOUSE_ACTION_MOTION
        }
    }
}

enum MouseButton {
    case left, right, middle, wheelUp, wheelDown

    var ghostty: GhosttyMouseButton {
        switch self {
        case .left: GHOSTTY_MOUSE_BUTTON_LEFT
        case .right: GHOSTTY_MOUSE_BUTTON_RIGHT
        case .middle: GHOSTTY_MOUSE_BUTTON_MIDDLE
        case .wheelUp: GHOSTTY_MOUSE_BUTTON_FOUR
        case .wheelDown: GHOSTTY_MOUSE_BUTTON_FIVE
        }
    }
}
