import Core
import Foundation

/// How a new order's branch is named: `<type>/<slug>`, with a number on the
/// end when that branch exists, and `chore/<adjective>-<noun>` when nothing
/// better is known.
///
/// Pure: the branches that exist are handed in.
enum OrderBranchName {
    /// The longest a slug runs, in words.
    static let maxWords = 5

    static let adjectives = [
        "brisk", "calm", "clever", "eager", "gentle", "keen", "lucky", "nimble", "quiet", "steady",
    ]

    static let nouns = [
        "badger", "comet", "falcon", "harbor", "lantern", "meadow", "otter", "pebble", "ridge", "willow",
    ]

    /// `slug` as lowercase ASCII words joined by dashes, at most ``maxWords``
    /// of them. Empty when there is nothing usable in it.
    static func cleanSlug(_ slug: String) -> String {
        let folded = slug.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var words: [String] = []
        var current = ""
        for scalar in folded.unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.prefix(maxWords).joined(separator: "-")
    }

    /// The branch for `slug`, which falls back to ``fallback(existing:using:)``
    /// when it cleans to nothing.
    static func make(
        type: OrderBranchType,
        slug: String,
        existing: Set<String>
    ) -> String {
        var generator = SystemRandomNumberGenerator()
        return make(type: type, slug: slug, existing: existing, using: &generator)
    }

    static func make(
        type: OrderBranchType,
        slug: String,
        existing: Set<String>,
        using generator: inout some RandomNumberGenerator
    ) -> String {
        let cleaned = cleanSlug(slug)
        guard !cleaned.isEmpty else { return fallback(existing: existing, using: &generator) }
        return unused("\(type.rawValue)/\(cleaned)", among: existing)
    }

    /// `chore/<adjective>-<noun>`, for when the naming call gave nothing.
    static func fallback(existing: Set<String>, using generator: inout some RandomNumberGenerator) -> String {
        let adjective = adjectives.randomElement(using: &generator) ?? adjectives[0]
        let noun = nouns.randomElement(using: &generator) ?? nouns[0]
        return unused("chore/\(adjective)-\(noun)", among: existing)
    }

    private static func unused(_ name: String, among existing: Set<String>) -> String {
        guard existing.contains(name) else { return name }
        var number = 2
        while existing.contains("\(name)-\(number)") { number += 1 }
        return "\(name)-\(number)"
    }
}
