import Foundation

/// Something on the screen that a click opens.
struct TerminalLink: Equatable {
    enum Target: Equatable {
        case url(URL)
        /// A file or folder that exists, and the place in it that was named.
        case file(URL, line: Int?, column: Int?)
    }

    var target: Target

    /// Found by looking at the text, as opposed to marked by the program
    /// (OSC 8). The program's wins where they overlap, and only these are
    /// thrown away and found again when the text around them changes.
    var isDetected: Bool
}
