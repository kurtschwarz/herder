import Core
import Foundation
import Observation

/// The files open in the editor pane, and which of them is showing.
///
/// One tab per file. Owns the set rather than borrowing it from the file
/// tree's selection: a selection goes when its file does, and a tab keeps
/// showing what it last read, struck through, until it is closed. The contents
/// are read from disk and re-read whenever the worktree's watcher says
/// something changed.
///
/// Only the tab showing is ever read. A background tab is a name until it is
/// clicked, including one whose file has since gone — the same argument as a
/// workspace not draining until a window shows it. Clicking it makes its
/// ``Document`` and its ``Buffer``, and from then on the text being edited
/// lives in the buffer, so it survives the tab being left.
///
/// Nothing is written until ``save()``. A change on disk under a buffer with
/// unsaved edits never replaces them.
@Observable
public final class EditorModel {
    /// Anything bigger is not opened. An editor holding a whole build log
    /// would spend its life laying it out.
    static let maxBytes = 1_000_000

    enum Content: Equatable {
        /// The text and the tokens found in it, as one value: see `SourceText`.
        case text(SourceText)
        case unavailable(Reason)
    }

    /// Why a file is not shown.
    enum Reason: Equatable {
        case notText
        case tooLarge
        case unreadable
    }

    private let store: WorkspaceRegistry
    private let files: any FileClient
    private let highlighter: any SyntaxHighlighter

    private var worktree: Workspace?

    /// The workspace the pane was last restored into. Everything the editor
    /// opens, saves and remembers goes through it; a file outside it is refused.
    private var scope: Workspace?

    /// A file asked for in a workspace the window has not got to yet, held
    /// until the restore that follows the switch. See ``requestOpen(_:line:column:)``.
    private var pendingOpen: (url: URL, line: Int?, column: Int?)?

    private var registration: Workspace.Registration?
    private var fileKey: PathKey?

    /// Counts each read, so one that comes back after a newer one started is
    /// dropped instead of overwriting it.
    private var generation = 0

    /// The files with a tab, in the order they were opened. Newest at the end,
    /// until ``move(_:to:)`` puts one elsewhere; there is no cap.
    public private(set) var tabs: [PathKey] = []

    /// The tabs that are pinned, which are the first of ``tabs``: see
    /// ``TabOrder``. Remembered with them.
    private(set) var pinned: Set<PathKey> = []

    /// The file showing, or `nil` when none is.
    public private(set) var file: URL?

    /// What was last read from the disk for it. `nil` until the first read
    /// finishes. Not what is being edited: that is in the buffer, and differs
    /// from this once anything is typed.
    private(set) var content: Content?

    /// What the file showing is written in, as the highlighter names it, or
    /// `nil` when nothing claims it or nothing has been read yet.
    private(set) var language: String?

    /// The file showing has gone from disk. Its last contents stay up.
    private(set) var isDeleted = false

    /// The documents behind the tabs that have been shown, per window. Not the
    /// workspace's: a buffer belongs to the window that made it.
    let documents = DocumentStore()

    /// The document for the file showing, once it has been read as text.
    private(set) var activeDocument: Document?

    /// Why the last save did not happen, until it is dismissed.
    private(set) var saveFailure: SaveFailure?

    /// Each document's buffer. Kept off the observation graph: it changes
    /// whenever a pane is made, and what the view reads is ``activeBuffer``.
    @ObservationIgnored
    private var buffers: [BufferHandle: Buffer] = [:]

    @ObservationIgnored
    private var rehighlight: Task<Void, Never>?

    /// How long typing has to stop before a big file is coloured again. The
    /// highlighter takes the whole document, so colouring every keystroke of
    /// one would parse it that many times.
    static let rehighlightDelay = Duration.milliseconds(50)

    /// Up to this many UTF-16 units a file is coloured on every keystroke. A
    /// parse takes about 4 ms at 24 KB and 33 ms at 190 KB, and runs off the main
    /// actor, so below this a new word is coloured as it is typed instead of
    /// when typing pauses.
    static let immediateRehighlightLimit = 100_000

    /// `highlighter` is injected rather than defaulted, even though it is pure —
    /// the same text gives the same tokens — because the real one lives in
    /// `Services` and a feature may not import that. The composition root picks
    /// it; `NoSyntaxHighlighter` is there for a test that wants the editor
    /// without the colour.
    public init(
        store: WorkspaceRegistry,
        files: any FileClient,
        highlighter: any SyntaxHighlighter
    ) {
        self.store = store
        self.files = files
        self.highlighter = highlighter
    }

    /// Which tab is showing, or `nil` when none is.
    var activeTab: PathKey? { fileKey }

    /// What the pane mounts for the file showing.
    var activeBuffer: Buffer? {
        activeDocument.flatMap { buffers[$0.buffer] }
    }

    /// Whether the tab for `key` has edits that are not on disk.
    func isDirty(_ key: PathKey) -> Bool {
        documents.documents(at: key).contains(where: \.isDirty)
    }

    /// The tabs as the bar draws them, with a folder added to the two that
    /// would otherwise both read `index.ts`.
    var openTabs: [EditorTab] {
        var counts: [String: Int] = [:]
        for key in tabs { counts[key.name, default: 0] += 1 }
        return tabs.map { key in
            EditorTab(
                key: key,
                name: key.name,
                folder: counts[key.name, default: 0] > 1 ? key.parent?.name : nil,
                isPinned: pinned.contains(key)
            )
        }
    }

    /// The worktree's folder name, then each folder down to the file showing.
    var breadcrumb: [String] {
        guard let worktree, let fileKey else { return [] }
        return worktree.components(of: fileKey)
    }

    // MARK: - Opening and closing

    /// Shows `url`, opening a tab for it if it has none. Does nothing for the
    /// file that is already showing, so a repeat selection keeps the scroll
    /// position, and nothing for a path outside the workspace the pane is
    /// restored into.
    public func open(_ url: URL) async {
        await open(PathKey(canonical: url.path(percentEncoded: false)), remembering: true)
    }

    /// Shows `url` with the caret at `line` and `column`, counting from one,
    /// even if the file was already showing.
    public func open(_ url: URL, line: Int?, column: Int?) async {
        let key = PathKey(canonical: url.path(percentEncoded: false))
        await open(key, remembering: true)
        guard let line, key == fileKey else { return }
        activeBuffer?.reveal(line: line, column: column)
    }

    /// Shows the tab for `key`. Nothing for a path with no tab: a tab bar can
    /// only ask for what it is drawing.
    func activate(_ key: PathKey) async {
        guard tabs.contains(key) else { return }
        await open(key, remembering: true)
    }

    /// Shows the tabs `workspace` had open when it was last shown, or empties
    /// the pane when there is nothing, or no workspace. Only the one that was
    /// showing is read, and only now, when something is showing the workspace:
    /// restoring a workspace at launch costs a watcher, and this is the cost
    /// of looking at it.
    ///
    /// A remembered file that has since gone is shown as deleted, and stays
    /// remembered. One that lies outside the workspace is dropped, tab, pin and
    /// active file alike, and the cleaned state is written back: it got there
    /// from an editor that was not scoped, and this repairs it.
    ///
    /// Then answers the open held by ``requestOpen(_:line:column:)``, if any,
    /// and drops it whether it was answered or not.
    public func restore(in workspace: Workspace?) async {
        close()
        let requested = pendingOpen
        pendingOpen = nil
        guard let workspace else { return }
        scope = workspace
        let state = workspace.uiState(EditorUIState.self)
        tabs = state.files.filter { $0.isInside(workspace.root) }
        pinned = Set(state.pinned).intersection(tabs)
        let remembered = state.active.flatMap { tabs.contains($0) ? $0 : nil }
        if let active = remembered ?? tabs.first {
            await open(active, remembering: false)
        }
        let dropped = tabs.count != state.files.count
            || pinned.count != state.pinned.count
            || (state.active != nil && state.active != fileKey)
        if dropped {
            remember(on: workspace)
        }
        if let requested {
            await open(requested.url, line: requested.line, column: requested.column)
        }
    }

    /// Asks for `url` to be shown at `line` and `column` once the pane is
    /// restored into the workspace holding it, which the window is already on
    /// its way to: the workspace opens asynchronously. If the pane is in it
    /// now, the file opens straight away.
    ///
    /// Answered by the next ``restore(in:)``, and dropped by it if the file is
    /// not inside, so a request for a workspace that never came cannot open the
    /// file somewhere else later.
    public func requestOpen(_ url: URL, line: Int?, column: Int?) async {
        let key = PathKey(canonical: url.path(percentEncoded: false))
        if let scope, key.isInside(scope.root) {
            await open(url, line: line, column: column)
        } else {
            pendingOpen = (url, line, column)
        }
    }

    /// Closes the tab for `key`. When it was the one showing, the tab to its
    /// right takes over, then the one to its left, then nothing.
    ///
    /// Right-neighbour rather than the last one used: that would need a
    /// history per window surviving closes and workspace switches, for a
    /// behaviour people describe as "it jumped somewhere weird".
    public func close(tab key: PathKey) async {
        guard let index = tabs.firstIndex(of: key) else { return }
        tabs.remove(at: index)
        pinned.remove(key)
        discard(documentsAt: key)

        guard key == fileKey else {
            worktree.map(remember(on:))
            return
        }
        let next = tabs.indices.contains(index) ? tabs[index] : tabs.last
        guard let next, let state = scope else {
            let leaving = worktree
            clear()
            leaving.map(remember(on:))
            return
        }
        await show(next, in: state, remembering: true)
    }

    /// Closes the tab showing. What ⌘W does, when there is one.
    public func closeActiveTab() async {
        guard let fileKey else { return }
        await requestClose(tab: fileKey)
    }

    /// Empties the pane and drops its tabs. What the workspace remembers is
    /// left alone: this is the pane letting go of a checkout, not the user
    /// closing anything.
    ///
    /// Documents with unsaved edits are kept, with their buffers, so that
    /// coming back to the checkout finds the typing where it was left.
    public func close() {
        clear()
        scope = nil
        tabs = []
        pinned = []
        for document in documents.documents where !document.isDirty { discard(document) }
    }

    /// The next tab along, wrapping at the end. What ⌘⇧] does.
    public func selectNextTab() async {
        await step(by: 1)
    }

    /// The previous tab, wrapping at the start. What ⌘⇧[ does.
    public func selectPreviousTab() async {
        await step(by: -1)
    }

    private func step(by offset: Int) async {
        guard
            let fileKey,
            tabs.count > 1,
            let index = tabs.firstIndex(of: fileKey)
        else { return }
        await activate(tabs[(index + offset + tabs.count) % tabs.count])
    }

    // MARK: - Reordering

    /// Puts the tab for `key` at `index`, clamped to its own side of the
    /// pinned tabs. Nothing for a path with no tab. Which tab is showing is
    /// not touched: moving a tab is not looking at it.
    func move(_ key: PathKey, to index: Int) {
        guard let from = tabs.firstIndex(of: key),
              TabOrder.move(&tabs, from: from, to: index, isPinned: pinned.contains)
        else { return }
        worktree.map(remember(on:))
    }

    /// Pins the tab for `key` or lets it go. Pinned tabs sit together at the
    /// front, in the order they were pinned; the rest keep their order behind
    /// them.
    func togglePin(_ key: PathKey) {
        guard let index = tabs.firstIndex(of: key) else { return }
        if pinned.remove(key) == nil { pinned.insert(key) }
        TabOrder.repin(&tabs, at: index, isPinned: pinned.contains)
        worktree.map(remember(on:))
    }

    /// Moves the tab showing one step along. What ⌘⌥⇧[ and ⌘⌥⇧] do.
    ///
    /// Stops at the ends where ``selectNextTab()`` wraps. Wrapping a selection
    /// is navigation; wrapping a move would carry a tab from one end of the
    /// strip to the other, which reads as a bug.
    public func moveActiveTab(by offset: Int) {
        guard canMoveActiveTab(by: offset), let fileKey, let index = tabs.firstIndex(of: fileKey) else { return }
        move(fileKey, to: index + offset)
    }

    /// Whether ``moveActiveTab(by:)`` would change anything, so a menu item
    /// can read as unavailable at the end it cannot go past.
    public func canMoveActiveTab(by offset: Int) -> Bool {
        guard let fileKey, let index = tabs.firstIndex(of: fileKey) else { return false }
        return TabOrder.run(of: index, in: tabs, isPinned: pinned.contains).contains(index + offset) && offset != 0
    }

    private func open(_ key: PathKey, remembering: Bool) async {
        guard key != fileKey, let state = scope, key.isInside(state.root) else { return }
        if !tabs.contains(key) { tabs.append(key) }
        await show(key, in: state, remembering: remembering)
    }

    /// Points the pane at `key` and reads it. The tab is already in ``tabs``.
    private func show(_ key: PathKey, in state: Workspace, remembering: Bool) async {
        registration?.cancel()
        worktree = state
        file = key.url
        fileKey = key
        content = nil
        activeDocument = nil
        language = nil
        isDeleted = false
        if remembering { remember(on: state) }
        registration = state.observe(
            onChange: { [weak self] in
                Task { await self?.reload() }
            },
            onMove: { [weak self] old, new in self?.follow(from: old, to: new) }
        )
        await reload()
    }

    /// Everything about what is on screen, without touching the tab list.
    private func clear() {
        registration?.cancel()
        registration = nil
        worktree = nil
        file = nil
        fileKey = nil
        content = nil
        activeDocument = nil
        language = nil
        isDeleted = false
        rehighlight?.cancel()
        generation += 1
    }

    private func discard(documentsAt key: PathKey) {
        for document in documents.documents(at: key) { discard(document) }
    }

    private func discard(_ document: Document) {
        documents.close(document)
        buffers[document.buffer] = nil
    }

    /// Writes the tabs down on the workspace they belong to.
    ///
    /// Observation reports reads, not writes, so the workspace cannot notice
    /// this for itself.
    private func remember(on state: Workspace) {
        let ui = state.uiState(EditorUIState.self)
        ui.files = tabs
        ui.active = fileKey
        ui.pinned = tabs.filter(pinned.contains)
        state.scheduleSnapshotSave()
    }

    // MARK: - Editing

    /// The person using the view changed the text in `buffer`.
    func bufferDidChange(_ buffer: Buffer) {
        guard let handle = buffers.first(where: { $0.value === buffer })?.key,
              let document = documents.documents.first(where: { $0.buffer == handle })
        else { return }

        document.bufferChanged(to: buffer.text)

        rehighlight?.cancel()
        let waits = buffer.storage.length > Self.immediateRehighlightLimit
        rehighlight = Task { [highlighter] in
            if waits {
                try? await Task.sleep(for: Self.rehighlightDelay)
                guard !Task.isCancelled else { return }
            }
            let text = buffer.text
            let tokens = await highlighter.tokens(in: text, ofFileNamed: document.key.path)
            guard !Task.isCancelled else { return }
            // Dropped by the buffer if typing went on while the parser ran.
            buffer.colour(tokens, foundIn: text)
        }
    }

    /// Writes the file showing, exactly as it is in the buffer: no newline
    /// added, no whitespace trimmed, no line endings changed. A save that
    /// normalised anything would turn a one-line edit into a whole-file diff.
    ///
    /// The disk is only written here. Writing wakes the watcher and the read
    /// that follows finds what was just written, which the document knows
    /// from its baseline, so there is nothing to suppress.
    ///
    /// A file that was deleted is written back. Its folder is not: making
    /// back a folder that was deleted is a bigger decision than saving.
    public func save() async {
        guard let activeDocument else { return }
        await save(activeDocument)
    }

    /// Whether the document was written.
    @discardableResult
    private func save(_ document: Document) async -> Bool {
        guard let buffer = buffers[document.buffer] else { return false }
        let key = document.key
        let text = buffer.text

        do {
            if let worktree = store.state(containing: key),
               let folder = key.parent, folder != worktree.root, worktree.exists(folder) == false {
                throw MissingFolder()
            }
            try await files.write(text, to: key.path)
        } catch {
            saveFailure = SaveFailure(name: key.name, reason: error.localizedDescription)
            return false
        }
        document.saved(text, buffer: buffer.text)
        if key == fileKey { isDeleted = false }
        return true
    }

    // MARK: - Unsaved work

    /// The files with edits that are not on disk, for a prompt to name.
    public var unsavedFiles: [String] {
        documents.dirty.map(\.key.name)
    }

    /// Writes every document with unsaved edits. Stops at the first that
    /// fails, which is then reported as any failed save is, and answers
    /// whether all of them went.
    public func saveAll() async -> Bool {
        for document in documents.dirty {
            guard await save(document) else { return false }
        }
        return true
    }

    /// The tab whose close is waiting on an answer.
    struct ClosePrompt: Equatable {
        let key: PathKey
        var name: String { key.name }
    }

    /// What is held while asking whether to lose a tab's edits.
    private(set) var closePrompt: ClosePrompt?

    enum CloseAnswer {
        case save, discard, cancel
    }

    /// Closes the tab for `key`, or asks first when it has unsaved edits. What
    /// the close button and ⌘W do: ``close(tab:)`` is the one that does not ask.
    func requestClose(tab key: PathKey) async {
        guard isDirty(key) else {
            await close(tab: key)
            return
        }
        closePrompt = ClosePrompt(key: key)
    }

    /// Carries out the answer to ``closePrompt``. A save that fails leaves the
    /// tab open, with the failure showing.
    func answer(_ answer: CloseAnswer) async {
        guard let prompt = closePrompt else { return }
        closePrompt = nil

        switch answer {
        case .cancel:
            return
        case .save:
            for document in documents.documents(at: prompt.key) where document.isDirty {
                guard await save(document) else { return }
            }
        case .discard:
            break
        }
        await close(tab: prompt.key)
    }

    // MARK: - A file that changed under unsaved edits

    /// Whether the file showing changed on disk while it held unsaved edits.
    var isStale: Bool { activeDocument?.isStale == true }

    /// Takes what is on disk, and the edits go.
    func reloadFromDisk() async {
        activeDocument?.discardEdits()
        await reload()
    }

    /// Keeps the buffer. It stays dirty, and saving it replaces what is on
    /// disk: the person has seen that it changed.
    func keepEdits() async {
        guard let document = activeDocument, let buffer = buffers[document.buffer],
              let text = try? await files.read(document.key.path, maxBytes: Self.maxBytes)
        else { return }
        document.keepBuffer(over: text, buffer: buffer.text)
    }

    /// Whether ``save()`` has anything to do.
    public var canSave: Bool { activeDocument?.isDirty == true }

    func dismissSaveFailure() {
        saveFailure = nil
    }

    private struct MissingFolder: LocalizedError {
        var errorDescription: String? { "The folder it was in no longer exists." }
    }

    // MARK: - Reading

    /// Reads the file showing again, unless it has gone, in which case what is
    /// showing stays. Most changes are to some other file, and a read that
    /// finds what the document already has must change nothing.
    ///
    /// The text is published as soon as it is read, and colour follows when the
    /// highlighter has it. Nothing a reader is waiting on is behind a parser.
    ///
    /// A buffer with unsaved edits is never replaced: the document is marked
    /// stale and the typing stays.
    ///
    /// Tokens landing separately is safe because they are only ever applied to
    /// the exact string they were found in — see `highlight` — and because a
    /// `SourceText` with no tokens is incomplete rather than wrong. What is not
    /// safe, and what `SourceText` exists to prevent, is tokens from one string
    /// reaching another.
    func reload() async {
        guard let worktree, let key = fileKey else { return }
        if worktree.exists(key) == false {
            isDeleted = true
            return
        }

        generation += 1
        let mine = generation
        let result: Content
        do {
            result = .text(SourceText(text: try await files.read(key.path, maxBytes: Self.maxBytes)))
        } catch FileClientError.tooLarge {
            result = .unavailable(.tooLarge)
        } catch FileClientError.notUTF8 {
            result = .unavailable(.notText)
        } catch FileClientError.notFound {
            guard mine == generation else { return }
            isDeleted = true
            return
        } catch {
            result = .unavailable(.unreadable)
        }
        guard mine == generation, key == fileKey else { return }

        isDeleted = false
        guard case .text(let source) = result else {
            activeDocument = nil
            language = nil
            if content != result { content = result }
            return
        }

        let document: Document
        let reading: Document.Reading
        if let existing = documents.documents(at: key).first {
            document = existing
            reading = existing.read(source.text)
        } else {
            document = documents.open(key, baseline: source.text)
            let buffer = Buffer(text: source.text)
            buffer.onEdit = { [weak self, weak buffer] in
                guard let buffer else { return }
                self?.bufferDidChange(buffer)
            }
            buffers[document.buffer] = buffer
            reading = .replace
        }
        activeDocument = document
        let named = highlighter.language(of: source.text, ofFileNamed: key.path)
        if language != named { language = named }

        switch reading {
        case .unchanged, .stale:
            // An identical read must not redraw, and with colour arriving
            // after the text that means leaving `content` alone rather than
            // resetting it: it would throw away the colour already on screen
            // and put it back a moment later. A worktree notifies every
            // observer when any folder in it is read, so expanding a folder in
            // the file tree reloads an unchanged file — and the flicker was
            // plain to see.
            if content == nil { content = .text(SourceText(text: document.baseline)) }
        case .replace:
            buffers[document.buffer]?.replace(with: source.text)
            content = result
            await highlight(source.text, at: key)
        }
    }

    /// Colours what is on screen, if it is still the text these tokens were
    /// found in.
    ///
    /// That check is the whole safety argument, and it is a better one than a
    /// generation counter: tokens are offsets into a particular string, so the
    /// question is not "is this read still the newest" but "is this still the
    /// text". A slow highlight whose file was rewritten and then written back
    /// is still correct; a fast one for a file that has since changed is not.
    private func highlight(_ text: String, at key: PathKey) async {
        let tokens = await highlighter.tokens(in: text, ofFileNamed: key.path)
        let highlighted = Content.text(SourceText(text: text, tokens: tokens))
        guard
            key == fileKey,
            case .text(let shown) = content,
            shown.text == text,
            content != highlighted
        else { return }
        content = highlighted
        activeBuffer?.colour(tokens, foundIn: text)
    }

    /// A rename of an open file, or of a folder above one, carries its tab
    /// along instead of leaving it pointing at a path that is no longer there.
    ///
    /// Renaming `A.swift` to `B.swift` with `B.swift` already open would leave
    /// two tabs on one path, which is a state with no correct rendering: they
    /// collapse into one, keeping the leftmost position, and it is the tab
    /// showing if either of the two was.
    private func follow(from old: PathKey, to new: PathKey) {
        guard tabs.contains(where: { $0.isInside(old) }) else { return }

        var moved: [PathKey] = []
        for key in tabs {
            let next = Workspace.moved(key, from: old, to: new)
            if !moved.contains(next) { moved.append(next) }
        }
        tabs = moved
        pinned = Set(pinned.map { Workspace.moved($0, from: old, to: new) })

        // The documents are re-keyed, not rebuilt: a rename costs no typing.
        let result = documents.move(from: old, to: new)
        for document in result.collapsed { discard(document) }
        if let active = activeDocument, result.collapsed.contains(where: { $0 === active }) {
            // The survivor is the other document at the path. Its text is not
            // what is on screen, so the next read puts it there.
            activeDocument = documents.documents(at: Workspace.moved(fileKey ?? old, from: old, to: new)).first
            content = nil
        }
        if let fileKey {
            let next = Workspace.moved(fileKey, from: old, to: new)
            self.fileKey = next
            file = next.url
        }
        worktree.map(remember(on:))
    }
}

/// Why a save did not happen, for the alert.
struct SaveFailure: Equatable {
    let name: String
    let reason: String
}

/// A tab as the bar draws it.
struct EditorTab: Identifiable, Equatable {
    let key: PathKey

    /// The file's own name.
    let name: String

    /// The folder holding it, shown only when another open tab has the same
    /// name. Worked out from the tab list, never stored: the clash goes when
    /// either of the two closes.
    let folder: String?

    var isPinned = false

    var id: PathKey { key }
}
