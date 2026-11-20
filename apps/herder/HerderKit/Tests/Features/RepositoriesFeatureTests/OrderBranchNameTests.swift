import Foundation
import Testing

import Core

@testable import RepositoriesFeature

@Suite struct OrderBranchNameTests {
    @Test func aBranchIsItsTypeAndSlug() {
        #expect(OrderBranchName.make(type: .feat, slug: "add-minimap", existing: []) == "feat/add-minimap")
        #expect(OrderBranchName.make(type: .fix, slug: "crash-on-save", existing: []) == "fix/crash-on-save")
        #expect(OrderBranchName.make(type: .chore, slug: "bump-deps", existing: []) == "chore/bump-deps")
    }

    @Test func aSlugIsCleanedToKebabCase() {
        #expect(OrderBranchName.cleanSlug("Add  Minimap!") == "add-minimap")
        #expect(OrderBranchName.cleanSlug("  --fix_the/thing--  ") == "fix-the-thing")
        #expect(OrderBranchName.cleanSlug("Café résumé") == "cafe-resume")
    }

    @Test func aSlugKeepsAtMostFiveWords() {
        #expect(OrderBranchName.cleanSlug("one two three four five six seven") == "one-two-three-four-five")
    }

    @Test func aSlugWithNothingUsableIsEmpty() {
        #expect(OrderBranchName.cleanSlug("!!!") == "")
        #expect(OrderBranchName.cleanSlug("") == "")
    }

    @Test func aTakenNameGetsTheNextFreeSuffix() {
        let taken: Set<String> = ["feat/add-minimap"]
        #expect(OrderBranchName.make(type: .feat, slug: "add-minimap", existing: taken) == "feat/add-minimap-2")

        let more: Set<String> = ["feat/add-minimap", "feat/add-minimap-2"]
        #expect(OrderBranchName.make(type: .feat, slug: "add-minimap", existing: more) == "feat/add-minimap-3")
    }

    @Test func aSuffixIsOnlyForTheSameType() {
        #expect(OrderBranchName.make(type: .fix, slug: "add-minimap", existing: ["feat/add-minimap"]) == "fix/add-minimap")
    }

    @Test func anUnusableSlugFallsBackToAnAdjectiveAndNoun() {
        var generator = SeededGenerator(seed: 1)
        let name = OrderBranchName.make(type: .feat, slug: "???", existing: [], using: &generator)
        #expect(name.hasPrefix("chore/"))
        let words = name.dropFirst("chore/".count).split(separator: "-").map(String.init)
        #expect(words.count == 2)
        #expect(OrderBranchName.adjectives.contains(words[0]))
        #expect(OrderBranchName.nouns.contains(words[1]))
    }

    @Test func theFallbackAvoidsTakenNames() {
        var generator = SeededGenerator(seed: 7)
        let first = OrderBranchName.fallback(existing: [], using: &generator)
        var again = SeededGenerator(seed: 7)
        let second = OrderBranchName.fallback(existing: [first], using: &again)
        #expect(second != first)
        #expect(second.hasPrefix("chore/"))
    }
}

/// The same numbers for the same seed, so a test can say what it saw.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
