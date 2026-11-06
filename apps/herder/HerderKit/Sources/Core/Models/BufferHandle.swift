import Foundation

/// Names a text buffer without being one.
///
/// `Core` knows a buffer exists and whether it is dirty; only the editor knows
/// what a buffer is. A handle stays the same when the file it holds is renamed,
/// which is what lets the editor keep a tab's text, selection and undo history
/// through a move.
public struct BufferHandle: Hashable, Sendable {
    private let id = UUID()

    public init() {}
}
