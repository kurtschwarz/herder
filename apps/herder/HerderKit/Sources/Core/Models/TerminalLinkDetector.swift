import Foundation

/// Finds what looks like a link in a line of terminal text.
///
/// Only looks at the text. Whether a path names anything is the caller's to
/// find out, which is what keeps this free of I/O: `and/or` is a candidate
/// here and not a link until the disk agrees.
public enum TerminalLinkDetector {
    // CONCURRENCY: immutable once made, and `NSRegularExpression` and
    // `NSDataDetector` are documented as safe to use from any thread.
    private nonisolated(unsafe) static let urlPattern = try! NSRegularExpression(
        pattern: #"[A-Za-z][A-Za-z0-9+.\-]*://[^\s<>"'`]+"#
    )
    private nonisolated(unsafe) static let detector = try! NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )
    private nonisolated(unsafe) static let tokenPattern = try! NSRegularExpression(
        pattern: #"[^\s"'`<>()\[\]{}|,;=*]+"#
    )
    private nonisolated(unsafe) static let locationPattern = try! NSRegularExpression(
        pattern: #"^(.+?)(?::(\d+)(?::(\d+))?)?$"#
    )
    private nonisolated(unsafe) static let fileNamePattern = try! NSRegularExpression(
        pattern: #"^[\w.@+\-]+\.[A-Za-z0-9]+$"#
    )

    public static func candidates(in text: String) -> [TerminalLinkCandidate] {
        guard !text.isEmpty else { return [] }
        let string = text as NSString
        let whole = NSRange(location: 0, length: string.length)
        var found: [TerminalLinkCandidate] = []

        func isTaken(_ range: Range<Int>) -> Bool {
            found.contains { $0.range.overlaps(range) }
        }

        for match in urlPattern.matches(in: text, range: whole) {
            let trimmed = trimmed(string.substring(with: match.range))
            guard let separator = trimmed.range(of: "://"), separator.upperBound < trimmed.endIndex,
                  let url = URL(string: trimmed)
            else { continue }
            let range = match.range.location..<match.range.location + trimmed.utf16.count
            if !isTaken(range) { found.append(TerminalLinkCandidate(kind: .url(url), range: range)) }
        }

        // The schemes with no `//`. A match that did not write its scheme out
        // is a bare domain or an address, which is not what was asked to open.
        for match in detector.matches(in: text, range: whole) {
            let raw = string.substring(with: match.range)
            guard let scheme = match.url?.scheme?.lowercased(), raw.lowercased().hasPrefix(scheme + ":") else {
                continue
            }
            let trimmed = trimmed(raw)
            guard let url = URL(string: trimmed) else { continue }
            let range = match.range.location..<match.range.location + trimmed.utf16.count
            if !isTaken(range) { found.append(TerminalLinkCandidate(kind: .url(url), range: range)) }
        }

        for match in tokenPattern.matches(in: text, range: whole) {
            var token = string.substring(with: match.range)
            while let last = token.last, ".,:;!?".contains(last) { token.removeLast() }
            guard !token.isEmpty, !token.contains("://"),
                  let reference = reference(from: token)
            else { continue }
            let range = match.range.location..<match.range.location + token.utf16.count
            if !isTaken(range) { found.append(TerminalLinkCandidate(kind: .path(reference), range: range)) }
        }

        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    // MARK: URLs

    private static let brackets: [Character: Character] = [")": "(", "]": "[", "}": "{", ">": "<"]

    /// Without the punctuation a sentence puts after a link, and the closing
    /// brackets it opened somewhere before: `(see https://x.y/z).` is
    /// `https://x.y/z`, while `Swift_(language)` keeps its own.
    static func trimmed(_ url: String) -> String {
        var url = url
        while let last = url.last {
            if ".,;:!?'\"".contains(last) {
                url.removeLast()
            } else if let open = brackets[last], url.filter({ $0 == last }).count > url.filter({ $0 == open }).count {
                url.removeLast()
            } else {
                break
            }
        }
        return url
    }

    // MARK: Paths

    private static func reference(from token: String) -> TerminalPathReference? {
        let string = token as NSString
        guard let match = locationPattern.firstMatch(in: token, range: NSRange(location: 0, length: string.length)) else {
            return nil
        }
        func number(_ group: Int) -> Int? {
            let range = match.range(at: group)
            guard range.location != NSNotFound, let value = Int(string.substring(with: range)), value > 0 else {
                return nil
            }
            return value
        }
        let path = string.substring(with: match.range(at: 1))
        let line = number(2)

        guard path.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        // A name with no folder in it is only a path when it says where in the
        // file, or `README.md` and `example.com` would all be looked up.
        let isFileName = fileNamePattern.firstMatch(in: path, range: NSRange(location: 0, length: (path as NSString).length)) != nil
        guard path.contains("/") || (line != nil && isFileName) else { return nil }

        return TerminalPathReference(path: path, line: line, column: line == nil ? nil : number(3))
    }
}
