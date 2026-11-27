import AppKit
import Core
import Foundation
import Observation

/// One terminal on screen: a process on a pseudo-terminal, the emulator that
/// makes sense of what it writes, and the view that draws it.
///
/// What a tab owns. It holds no idea of tabs, workspaces or windows, so a
/// terminal for an agent session is the same object.
@Observable
public final class TerminalScreen {
    /// Scrollback kept, in lines.
    public static let scrollbackLines = 10_000

    /// Counts bells. A tab that watches it can flash when it changes.
    public private(set) var bellCount = 0

    /// Where the shell last said it was (OSC 7), if it ever has.
    public private(set) var reportedDirectory: URL?

    /// What the program last called itself (OSC 0 or 2), if it ever has.
    public private(set) var title: String?

    /// What the program says it is doing (OSC 7501), a record per id, the
    /// one updated longest ago first. Empty when it has said nothing. A
    /// record without an app has its nearest ancestor's.
    public var programStatuses: [ProgramStatus] {
        statusRecords.map { record in
            guard record.app.isEmpty else { return record }
            var resolved = record
            var parent = record.id
            while !parent.isEmpty, resolved.app.isEmpty {
                parent = parent.lastIndex(of: "/").map { String(parent[..<$0]) } ?? ""
                resolved.app = statusRecords.first { $0.id == parent }?.app ?? ""
            }
            return resolved
        }
    }

    /// The most records kept. The spec asks for at least 64 and at most 256.
    static let statusRecordLimit = 256

    private var statusRecords: [ProgramStatus] = []

    /// How many chunks of output have arrived. A count rather than a time, so
    /// a watcher can tell "something happened since I last looked" against
    /// whatever clock it has.
    @ObservationIgnored public private(set) var outputCount = 0

    /// The process ended and its output has all been drawn.
    public private(set) var hasEnded = false

    /// This terminal's view has the keyboard. What the window's menu commands
    /// read to decide whether ⌘W means a terminal tab or an editor one.
    public internal(set) var isFocused = false

    /// Asked for instead of sending a key to a process that is gone: what to
    /// do when a key is pressed in a terminal that has nothing left to hear it.
    @ObservationIgnored public var onKeyWhileEnded: (() -> Void)?

    /// Told each time the person presses Return: what a terminal can say of
    /// someone having said something to the program in it.
    @ObservationIgnored public var onSubmit: (() -> Void)?

    /// Asked for when a click lands on a file, with the line and column the
    /// text named, if it did. Where a file opens is not the terminal's to say,
    /// so a screen with nobody to ask hands it to the system.
    @ObservationIgnored public var onOpenFile: ((URL, Int?, Int?) -> Void)?

    @ObservationIgnored let emulator: TerminalEmulator
    @ObservationIgnored private let session: any PTYSession
    @ObservationIgnored weak var view: TerminalNSView?

    @ObservationIgnored private let input: AsyncStream<Data>.Continuation
    @ObservationIgnored private(set) var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var refreshing: Task<Void, Never>?
    @ObservationIgnored private var resizing: Task<Void, Never>?
    @ObservationIgnored private var refreshPending = false
    @ObservationIgnored private var size: PTYSize

    /// `workingDirectory` is where the process starts: what a relative path in
    /// its output is taken from until it says where it has got to.
    public init(session: any PTYSession, size: PTYSize, workingDirectory: URL? = nil) {
        self.session = session
        self.size = size
        emulator = TerminalEmulator(
            columns: Int(size.columns), rows: Int(size.rows), scrollbackLines: Self.scrollbackLines
        )
        emulator.workingDirectory = workingDirectory

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        input = continuation

        emulator.onReply = { [input] data in input.yield(data) }
        emulator.onBell = { [weak self] in self?.bellCount += 1 }
        emulator.onWorkingDirectory = { [weak self, emulator] directory in
            self?.reportedDirectory = directory
            // A report that says nothing usable leaves the last place known.
            if let directory { emulator.workingDirectory = directory }
        }
        emulator.onTitle = { [weak self] in self?.title = $0.isEmpty ? nil : $0 }
        emulator.onProgramStatus = { [weak self] in self?.record($0) }
        emulator.onClipboardWrite = { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        // One consumer, so what is typed, pasted and answered goes to the
        // process in the order it happened. A task per write would not.
        tasks.append(Task { [session] in
            for await data in stream { await session.write(data) }
        })
        tasks.append(Task { [weak self, session] in
            for await chunk in session.output {
                guard let self else { return }
                outputCount += 1
                emulator.write(chunk)
                scheduleRefresh()
                // A flood arrives as fast as it is asked for, so without this
                // the loop would hold the main actor until it stopped, and
                // the window could not draw it or take the ^C that ends it.
                await Task.yield()
            }
            self?.finish()
        })
    }

    deinit {
        input.finish()
        for task in tasks { task.cancel() }
        refreshing?.cancel()
        resizing?.cancel()
    }

    // MARK: Output

    /// Draws what changed, once, however many chunks arrived since the last
    /// time: a command that prints a megabyte makes thousands.
    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        // Held one at a time: an agent's spinner refreshes for as long as it
        // runs, and a handle kept for each would never be let go.
        refreshing = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(8))
            self?.refresh()
        }
    }

    func refresh() {
        refreshPending = false
        let shape = emulator.mouseShape
        let changed = emulator.update()
        view?.invalidate(rows: changed)
        if emulator.mouseShape != shape { view?.refreshCursor() }
    }

    private func finish() {
        refresh()
        // Nothing is working or waiting once the program is gone. What it
        // finished, or failed at, is still news.
        statusRecords.removeAll { $0.state == .working || $0.state == .blocked }
        hasEnded = true
    }

    /// A report replaces its record whole, so what it leaves out is gone.
    private func record(_ report: TerminalEmulator.ProgramStatusReport) {
        switch report {
        case .put(let status):
            statusRecords.removeAll { $0.id == status.id }
            statusRecords.append(status)
            if statusRecords.count > Self.statusRecordLimit { statusRecords.removeFirst() }
        case .clear(let id):
            statusRecords.removeAll { $0.isWithin(id) }
        }
    }

    /// Prints a line of Herder's own after what the process wrote. Not sent to
    /// the process: it is the terminal telling the person something.
    public func announce(_ text: String) {
        emulator.write(Data("\r\n\(text)\r\n".utf8))
        refresh()
    }

    // MARK: Input

    /// Sends `data` to the process. `submits` when it is the Return key,
    /// which is told by the key, not the bytes: a program can ask for Return
    /// to be sent as something other than `\r`.
    func send(_ data: Data, submits: Bool = false) {
        guard !data.isEmpty else { return }
        // Typing goes to the bottom of the scrollback, as in every terminal.
        if !emulator.scroll.isAtBottom {
            emulator.scrollToBottom()
            refresh()
        }
        input.yield(data)
        if submits { onSubmit?() }
    }

    /// Types `text`, as if at the keyboard: a `\r` in it is Return.
    public func send(text: String) {
        send(Data(text.utf8), submits: text.contains("\r"))
    }

    /// Whether the program asked for pasted text to be bracketed.
    public var isBracketedPasteOn: Bool { emulator.isBracketedPasteOn }

    /// Pastes `text`, bracketed if the program asked for that.
    public func paste(_ text: String) {
        send(emulator.encodePaste(text))
    }

    /// Presses Ctrl+V, which is how an agent is told to read an image off the
    /// clipboard itself. Goes through the key encoder, since a program in the
    /// kitty keyboard mode does not take the bare `0x16`.
    func pasteImage() {
        send(emulator.encode(key: 9, action: .press, modifiers: [.control], text: nil, unshifted: 0x76))
    }

    /// The text on the screen now, a line to a row, without trailing blanks.
    public var visibleText: String {
        emulator.cells
            .map { row in row.map { $0.text.isEmpty ? " " : $0.text }.joined().replacing(/\s+$/, with: "") }
            .joined(separator: "\n")
    }

    /// What is selected, for the clipboard.
    public var selectedText: String? { emulator.selectedText }

    // MARK: Links

    /// Opens what a click landed on.
    func open(_ target: TerminalLink.Target) {
        switch target {
        case .url(let url):
            NSWorkspace.shared.open(url)
        case .file(let url, let line, let column):
            if let onOpenFile { onOpenFile(url, line, column) } else { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: Size

    /// The grid the view has room for. Tells the process, which is what makes
    /// `vim` redraw and a shell wrap at the right column.
    func resize(columns: Int, rows: Int, cellWidth: Int, cellHeight: Int) {
        guard columns != emulator.columns || rows != emulator.rows else { return }
        emulator.resize(columns: columns, rows: rows, cellWidth: cellWidth, cellHeight: cellHeight)
        size = PTYSize(columns: UInt16(columns), rows: UInt16(rows))
        let size = size
        // Each waits for the one before, so the process hears the sizes in order.
        resizing = Task { [session, previous = resizing] in
            await previous?.value
            await session.resize(size)
        }
        refresh()
    }

    /// Moves focus to this terminal's view.
    public func focus() {
        guard let view, let window = view.window else { return }
        window.makeFirstResponder(view)
    }
}
