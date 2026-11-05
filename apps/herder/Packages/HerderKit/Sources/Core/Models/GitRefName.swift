import Foundation

/// The rules `git check-ref-format` applies to a branch name, so a name can be
/// refused while it is being typed instead of when `git` rejects it.
public enum GitRefName {
    public enum Problem: Equatable {
        case empty
        /// Why the name is not allowed, worded to finish "A branch name ...".
        case invalid(String)
    }

    private static let forbidden: Set<Character> = ["~", "^", ":", "?", "*", "[", "\\"]

    /// `nil` when `name` is a valid branch name.
    public static func problem(in name: String) -> Problem? {
        guard !name.isEmpty else { return .empty }

        if name.hasPrefix("-") { return .invalid("can't start with a dash") }
        if name == "@" { return .invalid("can't be just @") }
        if name.hasPrefix("/") || name.hasSuffix("/") { return .invalid("can't start or end with a slash") }
        if name.contains("//") { return .invalid("can't have an empty part between slashes") }
        if name.contains("..") { return .invalid("can't contain two dots in a row") }
        if name.contains("@{") { return .invalid("can't contain @{") }
        if name.hasSuffix(".") { return .invalid("can't end with a dot") }

        for character in name {
            if character.isWhitespace { return .invalid("can't contain spaces") }
            if character.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) {
                return .invalid("can't contain control characters")
            }
            if forbidden.contains(character) { return .invalid("can't contain \(character)") }
        }

        for part in name.split(separator: "/") {
            if part.hasPrefix(".") { return .invalid("can't have a part starting with a dot") }
            if part.hasSuffix(".lock") { return .invalid("can't have a part ending in .lock") }
        }
        return nil
    }
}
