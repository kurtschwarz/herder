import Core
import Foundation
import Observation

/// The file shown in the editor pane.
///
/// Read-only, one file at a time. Owns which file is open rather than
/// borrowing it from the file tree's selection: a selection goes when its file
/// does, and the pane keeps showing what it last read, struck through, until
/// something else is opened or the worktree changes. The contents are read
/// from disk and re-read whenever the worktree's watcher says something
/// changed.
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

    /// The file open, or `nil` when none is.
    private(set) var file: URL?

    /// What was last read from it. `nil` until the first read finishes.
    private(set) var content: Content?

    /// The file has gone from disk. Its last contents stay up.
    private(set) var isDeleted = false

    /// Changes whenever a different file is opened, and not when the open file
    /// is renamed or rewritten. The view uses it to know when to go back to
    /// the top.
    private(set) var session = 0

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

    /// The worktree's folder name, then each folder down to the file.
    var breadcrumb: [String] {
        guard let worktree, let fileKey else { return [] }
        return worktree.components(of: fileKey)
    }

    /// Shows `url`. Does nothing for the file that is already open, so a repeat
    /// selection keeps the scroll position, and nothing for a path outside every
    /// worktree being held.
    public func open(_ url: URL) async {
        await open(url, remembering: true)
    }

    /// Shows what `workspace` had open when it was last shown, or empties the
    /// pane when there is nothing, or no workspace. The file is read only now,
    /// when something is showing the workspace: restoring a workspace at launch
    /// costs a watcher, and this is the cost of looking at it.
    ///
    /// A remembered file that has since gone is shown as deleted, and stays
    /// remembered.
    public func restore(in workspace: Workspace?) async {
        close()
        guard let workspace, let key = workspace.uiState(EditorUIState.self).file else { return }
        await open(key.url, remembering: false)
    }

    private func open(_ url: URL, remembering: Bool) async {
        let key = PathKey(canonical: url.path(percentEncoded: false))
        guard key != fileKey, let state = store.state(containing: key) else { return }

        if remembering {
            state.uiState(EditorUIState.self).file = key
            // Observation reports reads, not writes, so the workspace cannot
            // notice this for itself.
            state.scheduleSnapshotSave()
        }
        registration?.cancel()
        worktree = state
        file = url
        fileKey = key
        content = nil
        isDeleted = false
        session += 1
        registration = state.observe(
            onChange: { [weak self] in
                Task { await self?.reload() }
            },
            onMove: { [weak self] old, new in self?.follow(from: old, to: new) }
        )
        await reload()
    }

    /// Empties the pane. What the workspace remembers is left alone: this is
    /// the pane letting go, not the user closing the file.
    public func close() {
        registration?.cancel()
        registration = nil
        worktree = nil
        file = nil
        fileKey = nil
        content = nil
        isDeleted = false
        generation += 1
    }

    /// Reads the file again, unless it has gone, in which case what is showing
    /// stays. The text is only replaced when it differs: most changes are to
    /// some other file, and an identical read must not redraw.
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

    /// A rename of the open file, or of a folder above it, carries the pane
    /// along instead of leaving it looking at a path that is no longer there.
    private func follow(from old: PathKey, to new: PathKey) {
        guard let fileKey, fileKey.isInside(old) else { return }
        let moved = Workspace.moved(fileKey, from: old, to: new)
        self.fileKey = moved
        file = moved.url
        worktree?.uiState(EditorUIState.self).file = moved
        worktree?.scheduleSnapshotSave()
    }
}
