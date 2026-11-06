import Foundation
import Observation

/// The documents being edited, and which of them have unsaved changes.
///
/// Not the tab list: a tab can exist before its file has been read, and a
/// document exists only once there is a buffer. What makes this a store of its
/// own is dirtiness — the tab bar, the close prompts and anything else that
/// has to ask "is there work here?" read it from one place.
@MainActor
@Observable
public final class DocumentStore {
    /// What a move did to the documents it touched.
    public struct Move {
        /// Documents now at a new path. The same documents, with the same
        /// buffers.
        public var moved: [Document] = []

        /// Documents dropped because a move landed on their path. Never dirty:
        /// the store does not throw away unsaved text. The caller frees their
        /// buffers.
        public var collapsed: [Document] = []
    }

    /// Open documents in the order they were made. More than one can share a
    /// path, after ``move(from:to:)`` lands on a path whose document has
    /// unsaved changes.
    public private(set) var documents: [Document] = []

    public init() {}

    /// The documents at `key`: one, or two after a move onto unsaved work.
    public func documents(at key: PathKey) -> [Document] {
        documents.filter { $0.key == key }
    }

    /// Every document with unsaved changes.
    public var dirty: [Document] {
        documents.filter(\.isDirty)
    }

    /// A document for `key` holding `baseline`, which is what the disk had.
    /// An existing one is returned as it is.
    @discardableResult
    public func open(_ key: PathKey, baseline: String) -> Document {
        if let existing = documents.first(where: { $0.key == key }) { return existing }
        let document = Document(key: key, baseline: baseline)
        documents.append(document)
        return document
    }

    /// Forgets `document`, returning it so its buffer can be freed. Whether
    /// that loses work is the caller's to have asked.
    @discardableResult
    public func close(_ document: Document) -> Document? {
        guard let index = documents.firstIndex(where: { $0 === document }) else { return nil }
        return documents.remove(at: index)
    }

    /// Follows a rename or move of `old` to `new`, a folder's contents with it.
    ///
    /// Documents are re-keyed, not rebuilt, so a rename costs no typing. When
    /// one lands on a path that has a document of its own, whichever of the
    /// two has nothing unsaved is collapsed into the other: the file on disk
    /// is one thing, and the clean one holds nothing the disk does not. The
    /// disk read that follows marks a dirty survivor stale.
    ///
    /// When both have unsaved edits neither is collapsed: both stay, at one
    /// path, and the disk read marks the displaced one stale.
    @discardableResult
    public func move(from old: PathKey, to new: PathKey) -> Move {
        var result = Move()
        for document in documents where document.key.isInside(old) {
            let target = PathKey(canonical: new.path + document.key.path.dropFirst(old.path.count))
            if target == document.key { continue }

            let others = documents.filter { $0.key == target && $0 !== document }
            if !document.isDirty, others.contains(where: \.isDirty) {
                result.collapsed.append(document)
                continue
            }
            result.collapsed += others.filter { !$0.isDirty }
            document.rekey(to: target)
            result.moved.append(document)
        }
        documents.removeAll { document in result.collapsed.contains { $0 === document } }
        return result
    }
}
