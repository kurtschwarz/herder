import Core
import Foundation
import Testing

@Suite struct GitChangeSummaryTests {
    @Test func readsBothCounts() {
        let summary = GitChangeSummary.parse(shortstat: " 3 files changed, 107 insertions(+), 19 deletions(-)\n")
        #expect(summary == GitChangeSummary(insertions: 107, deletions: 19))
    }

    @Test func readsASingularCount() {
        let summary = GitChangeSummary.parse(shortstat: " 1 file changed, 1 insertion(+), 1 deletion(-)\n")
        #expect(summary == GitChangeSummary(insertions: 1, deletions: 1))
    }

    @Test func aMissingCountIsZero() {
        #expect(GitChangeSummary.parse(shortstat: " 1 file changed, 4 insertions(+)\n")
            == GitChangeSummary(insertions: 4, deletions: 0))
        #expect(GitChangeSummary.parse(shortstat: " 2 files changed, 9 deletions(-)\n")
            == GitChangeSummary(insertions: 0, deletions: 9))
    }

    @Test func noOutputIsNoChange() {
        #expect(GitChangeSummary.parse(shortstat: "") == GitChangeSummary(insertions: 0, deletions: 0))
    }
}

@Suite struct GitDefaultBranchTests {
    @Test func originHeadComesFirst() {
        let branch = GitDefaultBranch.resolve(originHead: "origin/trunk") { _ in true }
        #expect(branch == "origin/trunk")
    }

    @Test func fallsBackToMainThenMaster() {
        #expect(GitDefaultBranch.resolve(originHead: nil) { ["main", "master"].contains($0) } == "main")
        #expect(GitDefaultBranch.resolve(originHead: nil) { $0 == "master" } == "master")
    }

    @Test func anOriginHeadThatDoesNotExistIsSkipped() {
        #expect(GitDefaultBranch.resolve(originHead: "origin/gone") { $0 == "main" } == "main")
    }

    @Test func nothingFoundIsNil() {
        #expect(GitDefaultBranch.resolve(originHead: nil) { _ in false } == nil)
    }
}
