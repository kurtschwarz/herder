import Foundation

/// What Cmd+V does with the clipboard, chosen from what it holds.
enum ClipboardPaste: Equatable {
    /// Files to paste as quoted paths.
    case paths(String)
    case text(String)
    /// Only a picture: the program reads it itself, after a Ctrl+V.
    case image

    /// The first of file links, text and an image that the clipboard holds, or
    /// `nil` when it holds none of them.
    static func choose(fileURLs: [URL], text: String?, hasImage: Bool) -> ClipboardPaste? {
        if !fileURLs.isEmpty { return .paths(quoted(fileURLs)) }
        if let text { return .text(text) }
        if hasImage { return .image }
        return nil
    }

    /// `urls` as a shell wants them, with a space after, as a drop on any terminal does.
    static func quoted(_ urls: [URL]) -> String {
        let words = urls.map { "'" + $0.path(percentEncoded: false).replacing("'", with: "'\\''") + "'" }
        return words.joined(separator: " ") + " "
    }
}
