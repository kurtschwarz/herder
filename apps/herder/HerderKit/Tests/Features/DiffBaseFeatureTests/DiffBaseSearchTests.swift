import Core
import Foundation
import Testing

@testable import DiffBaseFeature

@Suite struct DiffBaseSearchTests {
    let refs = [
        GitRef(name: "origin/main", kind: .remoteBranch, date: Date(timeIntervalSince1970: 300)),
        GitRef(name: "feature/search", kind: .branch, date: Date(timeIntervalSince1970: 200)),
        GitRef(name: "v1.0", kind: .tag, date: Date(timeIntervalSince1970: 100)),
    ]
    let commits = (1...8).map {
        GitCommit(sha: String(repeating: String($0), count: 40), subject: "commit \($0)", date: Date(timeIntervalSince1970: Double($0)))
    }

    @Test func anEmptySearchListsTheRefsAndTheLastFiveCommits() {
        let rows = DiffBaseSearch.rows(for: "", refs: refs, commits: commits)

        #expect(rows.count == 3 + 5)
        #expect(rows.first == .ref(refs[0]))
        #expect(rows.last == .commit(commits[4]))
    }

    @Test func aSearchKeepsTheRefsWhoseNameHoldsItInTheirOrder() {
        let rows = DiffBaseSearch.rows(for: "MAIN", refs: refs, commits: commits)
        #expect(rows == [.ref(refs[0])])
    }

    @Test func returnPicksTheOnlyMatch() async {
        let rows = DiffBaseSearch.rows(for: "v1", refs: refs, commits: commits)
        let picked = await DiffBaseSearch.submission(for: "v1", rows: rows, commit: { _ in nil })
        #expect(picked == "v1.0")
    }

    @Test func returnWithSeveralMatchesPicksNothing() async {
        let rows = DiffBaseSearch.rows(for: "/", refs: refs, commits: commits)
        #expect(rows.count == 2)
        #expect(await DiffBaseSearch.submission(for: "/", rows: rows, commit: { _ in nil }) == nil)
    }

    @Test func returnPicksAPastedSHAGitConfirms() async {
        let commit = commits[0]
        let picked = await DiffBaseSearch.submission(
            for: "1111111", rows: [], commit: { $0 == "1111111" ? commit : nil }
        )
        #expect(picked == commit.sha)
    }

    @Test func returnIgnoresAShaGitDoesNotKnow() async {
        #expect(await DiffBaseSearch.submission(for: "deadbeef", rows: [], commit: { _ in nil }) == nil)
        #expect(await DiffBaseSearch.submission(for: "zzzz", rows: [], commit: { _ in commits[0] }) == nil)
    }
}
