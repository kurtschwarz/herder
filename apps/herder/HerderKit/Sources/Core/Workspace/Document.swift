import Foundation
import Observation

/// One file being edited: where it is, which buffer holds its text, and how
/// that text compares with the disk.
///
/// Holds metadata, not the text being edited. That lives in the editor, behind
/// ``buffer``. What is kept here is ``baseline``, the text as the disk last had
/// it, which is the other side of every comparison: whether the buffer is
/// dirty, and whether a read of the disk is news.
@MainActor
@Observable
public final class Document {
    /// What a read of the disk meant for a document.
    public enum Reading: Equatable {
        /// The disk holds what this document last saw. Nothing to do, and in
        /// particular nothing to redraw: this is what our own save comes back as.
        case unchanged

        /// The disk changed and the buffer had no edits, so the buffer should
        /// take the new text. ``Document/baseline`` already has.
        case replace

        /// The disk changed under unsaved edits. The buffer is left alone and
        /// ``Document/isStale`` says so.
        case stale
    }

    public private(set) var key: PathKey
    public let buffer: BufferHandle

    /// The file's text as the disk last had it, from the last read or the last
    /// save.
    public private(set) var baseline: String

    /// Whether the buffer differs from ``baseline``. Comparing, not counting
    /// edits: typing a letter and deleting it again is not a change.
    public private(set) var isDirty = false

    /// Whether the disk has moved on from ``baseline`` while the buffer holds
    /// edits, so saving would overwrite what is there.
    public private(set) var isStale = false

    public init(key: PathKey, buffer: BufferHandle = BufferHandle(), baseline: String) {
        self.key = key
        self.buffer = buffer
        self.baseline = baseline
    }

    /// The buffer's text is now `text`. Compared and not kept.
    public func bufferChanged(to text: String) {
        isDirty = text != baseline
    }

    /// `written` has just gone to the disk. `buffer` is what the buffer holds
    /// now, which differs if typing went on during the write.
    public func saved(_ written: String, buffer: String) {
        baseline = written
        isDirty = buffer != written
        isStale = false
    }

    /// The disk was read and held `text`.
    public func read(_ text: String) -> Reading {
        guard text != baseline else {
            isStale = false
            return .unchanged
        }
        guard isDirty else {
            baseline = text
            return .replace
        }
        isStale = true
        return .stale
    }

    func rekey(to key: PathKey) {
        self.key = key
    }
}
