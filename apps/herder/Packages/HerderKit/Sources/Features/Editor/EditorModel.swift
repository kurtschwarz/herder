import Core
import Foundation
import Observation

/// The files open in the editor pane, and which of them is showing.
///
/// Read-only, one tab per file. Owns the set rather than borrowing it from the
/// file tree's selection: a selection goes when its file does, and a tab keeps
/// showing what it last read, struck through, until it is closed. The contents
/// are read from disk and re-read whenever the worktree's watcher says
/// something changed.
///
/// Only the tab showing is ever read. A background tab is a name until it is
/// clicked, including one whose file has since gone — the same argument as a
/// workspace not draining until a window shows it.
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
    private var registration: Workspace.Registration?
    private var fileKey: PathKey?

    /// Counts each read, so one that comes back after a newer one started is
    /// dropped instead of overwriting it.
    private var generation = 0

    /// The files with a tab, in the order they were opened. Newest at the end;
    /// nothing reorders them and there is no cap.
    public private(set) var tabs: [PathKey] = []

    /// The file showing, or `nil` when none is.
    public private(set) var file: URL?

    /// What was last read from it. `nil` until the first read finishes.
    private(set) var content: Content?

    /// The file showing has gone from disk. Its last contents stay up.
    private(set) var isDeleted = false

    /// Changes whenever a different file is shown, and not when the showing
    /// file is renamed or rewritten. The view uses it to know when to restore
    /// a scroll position.
    private(set) var session = 0

    /// Where each tab was last scrolled to. In memory only, and kept for the
    /// model's whole life rather than the workspace's, so switching checkouts
    /// and coming back keeps your place. An offset is sixteen bytes, where
    /// holding each tab's text would be a megabyte apiece with the watcher to
    /// invalidate it against.
    ///
    /// `@ObservationIgnored` on purpose: it is written on every scroll tick,
    /// and tracked it would redraw the pane each time.
    @ObservationIgnored
    private var offsets: [PathKey: CGPoint] = [:]

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

    /// The tabs as the bar draws them, with a folder added to the two that
    /// would otherwise both read `index.ts`.
    var openTabs: [EditorTab] {
        var counts: [String: Int] = [:]
        for key in tabs { counts[key.name, default: 0] += 1 }
        return tabs.map { key in
            EditorTab(
                key: key,
                name: key.name,
                folder: counts[key.name, default: 0] > 1 ? key.parent?.name : nil
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
    /// position, and nothing for a path outside every worktree being held.
    public func open(_ url: URL) async {
        await open(PathKey(canonical: url.path(percentEncoded: false)), remembering: true)
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
    /// remembered.
    public func restore(in workspace: Workspace?) async {
        close()
        guard let workspace else { return }
        let state = workspace.uiState(EditorUIState.self)
        tabs = state.files
        guard let active = state.active ?? state.files.first else { return }
        await open(active, remembering: false)
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
        offsets[key] = nil

        guard key == fileKey else {
            worktree.map(remember(on:))
            return
        }
        let next = tabs.indices.contains(index) ? tabs[index] : tabs.last
        guard let next, let state = store.state(containing: next) else {
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
        await close(tab: fileKey)
    }

    /// Empties the pane and drops its tabs. What the workspace remembers is
    /// left alone: this is the pane letting go of a checkout, not the user
    /// closing anything.
    public func close() {
        clear()
        tabs = []
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

    private func open(_ key: PathKey, remembering: Bool) async {
        guard key != fileKey, let state = store.state(containing: key) else { return }
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
        isDeleted = false
        session += 1
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
        isDeleted = false
        generation += 1
    }

    /// Writes the tabs down on the workspace they belong to.
    ///
    /// Observation reports reads, not writes, so the workspace cannot notice
    /// this for itself.
    private func remember(on state: Workspace) {
        let ui = state.uiState(EditorUIState.self)
        ui.files = tabs
        ui.active = fileKey
        state.scheduleSnapshotSave()
    }

    // MARK: - Scrolling

    /// Where `key` was left, or the top for a tab never scrolled.
    func offset(of key: PathKey) -> CGPoint {
        offsets[key] ?? .zero
    }

    /// Records where a tab was when the pane moved off it.
    func rememberOffset(_ offset: CGPoint, of key: PathKey) {
        offsets[key] = offset
    }

    // MARK: - Reading

    /// Reads the file showing again, unless it has gone, in which case what is
    /// showing stays. The text is only replaced when it differs: most changes
    /// are to some other file, and an identical read must not redraw.
    ///
    /// The text is published as soon as it is read, and colour follows when the
    /// highlighter has it. Nothing a reader is waiting on is behind a parser.
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
            if content != result { content = result }
            return
        }

        // An identical read must not redraw, and with colour arriving after the
        // text that means comparing the text rather than the whole value.
        // `result` never carries tokens, so comparing values would throw away
        // the colour already on screen and put it back a moment later. A worktree
        // notifies every observer when any folder in it is read, so expanding a
        // folder in the file tree reloads an unchanged file — and the flicker was
        // plain to see.
        guard shownText != source.text else { return }
        content = result
        await highlight(source.text, at: key)
    }

    /// The text on screen, or `nil` when the pane is empty or showing a reason
    /// instead of a file.
    private var shownText: String? {
        guard case .text(let source) = content else { return nil }
        return source.text
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
        offsets = Dictionary(
            offsets.map { (Workspace.moved($0.key, from: old, to: new), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        if let fileKey {
            let next = Workspace.moved(fileKey, from: old, to: new)
            self.fileKey = next
            file = next.url
        }
        worktree.map(remember(on:))
    }
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

    var id: PathKey { key }
}
