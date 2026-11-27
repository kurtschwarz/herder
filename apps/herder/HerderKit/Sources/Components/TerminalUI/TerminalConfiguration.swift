import Foundation

/// What a terminal is told when it is made: the tweaks that differ between
/// one terminal and the next, such as a shell's and an agent's.
///
/// Fixed for the terminal's life. A change reaches the terminals made after it.
public struct TerminalConfiguration: Sendable, Equatable {
    /// Lines of history kept above the screen. 0 keeps all of it.
    public var scrollbackLines: Int

    public init(scrollbackLines: Int = 10_000) {
        self.scrollbackLines = scrollbackLines
    }

    public static let `default` = TerminalConfiguration()
}
