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
