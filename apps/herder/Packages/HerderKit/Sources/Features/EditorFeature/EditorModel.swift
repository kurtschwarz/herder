import Clients
import Foundation
import Models
import Observation
import Worktrees

/// The file shown in the editor pane.
///
/// Read-only, one file at a time. Owns which file is open rather than
/// borrowing it from the explorer's selection: a selection goes when its file
/// does, and the pane keeps showing what it last read, struck through, until
/// something else is opened or the worktree changes. The contents are read
/// from disk and re-read whenever the worktree's watcher says something
/// changed.
@Observable
public final class EditorModel {
    /// Anything bigger is not opened. An editor holding a whole build log
    /// would spend its life laying it out.
    static let maxBytes = 1_000_000

    public enum Content: Equatable {
        case text(String)
        case unavailable(Reason)
    }

    /// Why a file is not shown.
    public enum Reason: Equatable {
        case notText
        case tooLarge
        case unreadable
    }

    private let store: WorktreeStateStore
    private let files: any FileClient

    private var worktree: WorktreeState?
    private var registration: WorktreeState.Registration?
    private var fileKey: PathKey?

    /// Counts each read, so one that comes back after a newer one started is
    /// dropped instead of overwriting it.
    private var generation = 0

    /// The file open, or `nil` when none is.
    public private(set) var file: URL?

    /// What was last read from it. `nil` until the first read finishes.
    public private(set) var content: Content?

    /// The file has gone from disk. Its last contents stay up.
    public private(set) var isDeleted = false

    /// Changes whenever a different file is opened, and not when the open file
    /// is renamed or rewritten. The view uses it to know when to go back to
    /// the top.
    public private(set) var session = 0

    public init(store: WorktreeStateStore, files: any FileClient) {
        self.store = store
        self.files = files
    }

    /// The worktree's folder name, then each folder down to the file.
    public var breadcrumb: [String] {
        guard let worktree, let fileKey else { return [] }
        return worktree.components(of: fileKey)
    }

    /// Shows `url`. Does nothing for the file that is already open, so a repeat
    /// selection keeps the scroll position, and nothing for a path outside every
    /// worktree being held.
    public func open(_ url: URL) async {
        let key = PathKey(canonical: url.path(percentEncoded: false))
        guard key != fileKey, let state = store.state(containing: key) else { return }

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

    /// Empties the pane. Called when the worktree changes: a file from the one
    /// before is stale context, not preserved context.
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
            result = .text(try await files.read(key.path, maxBytes: Self.maxBytes))
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
        if content != result { content = result }
    }

    /// A rename of the open file, or of a folder above it, carries the pane
    /// along instead of leaving it looking at a path that is no longer there.
    private func follow(from old: PathKey, to new: PathKey) {
        guard let fileKey, fileKey.isInside(old) else { return }
        let moved = WorktreeState.moved(fileKey, from: old, to: new)
        self.fileKey = moved
        file = moved.url
    }
}
