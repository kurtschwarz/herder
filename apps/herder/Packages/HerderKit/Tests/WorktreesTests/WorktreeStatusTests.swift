import Clients
import Foundation
import Models
import Testing
import Worktrees

@Suite struct WorktreeStatusTests {
    let root = PathKey(canonical: "/code/api")

    func status(_ entries: [String: GitStatus]) -> WorktreeStatus {
        WorktreeStatus(GitWorktreeStatus(
            root: root,
            entries: Dictionary(uniqueKeysWithValues: entries.map { (root.appending($0.key), $0.value) })
        ))
    }

    func key(_ relative: String) -> PathKey { root.appending(relative) }

    @Test func aPathGitReportedKeepsItsOwnStatus() {
        let status = status(["a.txt": .tracked(staged: .unchanged, unstaged: .modified)])

        #expect(status.status(of: key("a.txt")) == .tracked(staged: .unchanged, unstaged: .modified))
    }

    @Test func gitSaysNothingAboutAnUnchangedPath() {
        #expect(status(["a.txt": .untracked]).status(of: key("b.txt")) == nil)
    }

    @Test func aPathTakesItsStatusFromACollapsedFolderAboveIt() {
        let status = status(["build": .ignored, "fresh": .untracked])

        #expect(status.status(of: key("build/deep/out.o")) == .ignored)
        #expect(status.status(of: key("fresh/deep/a.txt")) == .untracked)
    }

    /// The one place the two can contend: a tracked file inside an ignored
    /// folder reads as what git said about it, not as ignored.
    @Test func aPathGitReportedWinsOverWhatItWouldInherit() {
        let status = status([
            "build": .ignored,
            "build/kept.txt": .tracked(staged: .unchanged, unstaged: .modified),
        ])

        #expect(status.status(of: key("build/kept.txt")) == .tracked(staged: .unchanged, unstaged: .modified))
        #expect(!status.isIgnored(key("build/kept.txt")))
    }

    @Test func ignoredIsInheritedButUntrackedIsNotIgnored() {
        let status = status(["build": .ignored, "fresh": .untracked])

        #expect(status.isIgnored(key("build")))
        #expect(status.isIgnored(key("build/deep/out.o")))
        #expect(!status.isIgnored(key("fresh")))
        #expect(!status.isIgnored(key("fresh/a.txt")))
    }

    @Test func nothingOutsideTheRootInheritsAnything() {
        let status = status(["build": .ignored])

        #expect(status.status(of: PathKey(canonical: "/elsewhere/build/out.o")) == nil)
    }

    @Test func aChangeMarksEveryFolderBetweenItAndTheRoot() {
        let status = status(["Sources/deep/App.swift": .tracked(staged: .added, unstaged: .unchanged)])

        #expect(status.rollup(of: key("Sources/deep")) == .modified)
        #expect(status.rollup(of: key("Sources")) == .modified)
        #expect(status.rollup(of: root) == .modified)
    }

    @Test func aFolderShowsTheHighestPrecedenceStateBelowIt() {
        let status = status([
            "Sources/a.txt": .untracked,
            "Sources/b.swift": .tracked(staged: .unchanged, unstaged: .modified),
            "Sources/c.swift": .unmerged,
        ])

        #expect(status.rollup(of: key("Sources")) == .unmerged)
    }

    @Test func untrackedIsTheWeakestMarkAndModifiedBeatsIt() {
        let untracked = status(["Sources/a.txt": .untracked])
        let both = status([
            "Sources/a.txt": .untracked,
            "Sources/b.swift": .tracked(staged: .unchanged, unstaged: .deleted),
        ])

        #expect(untracked.rollup(of: key("Sources")) == .untracked)
        #expect(both.rollup(of: key("Sources")) == .modified)
    }

    /// Otherwise every repository with a build folder in it wears a marker on
    /// its root for ever, and the marker stops meaning anything.
    @Test func anIgnoredFolderRaisesNoMarkAnywhere() {
        let status = status(["build": .ignored])

        #expect(status.rollup(of: root) == nil)
        #expect(status.rollup(of: key("build")) == nil)
    }

    /// Ignored is terminal downward as well: the fade already says the folder
    /// is not what the work is about.
    @Test func aChangeBuriedInsideAnIgnoredFolderRaisesNoMark() {
        let status = status([
            "build": .ignored,
            "build/kept.txt": .tracked(staged: .unchanged, unstaged: .modified),
        ])

        #expect(status.rollup(of: key("build")) == nil)
        #expect(status.rollup(of: root) == nil)
    }

    /// A deletion draws no row of its own, so the mark on the folder above it
    /// is the only thing that says it happened.
    @Test func aDeletedFileStillMarksTheFolderItWasIn() {
        let status = status(["Sources/Gone.swift": .tracked(staged: .deleted, unstaged: .unchanged)])

        #expect(status.rollup(of: key("Sources")) == .modified)
    }

    @Test func anEmptyStatusKnowsNothing() {
        #expect(WorktreeStatus.empty.status(of: key("a.txt")) == nil)
        #expect(!WorktreeStatus.empty.isIgnored(key("a.txt")))
        #expect(WorktreeStatus.empty.rollup(of: root) == nil)
    }
}
