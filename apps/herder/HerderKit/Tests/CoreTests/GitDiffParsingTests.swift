import Core
import Foundation
import Testing

@Suite struct GitDiffParsingTests {
    @Test func changedFilesJoinStatusAndCountsAndSortByPath() {
        let nameStatus = "M\0b/z.swift\0A\0a.txt\0D\0gone.txt\0"
        let numstat = "3\t1\tb/z.swift\0" + "5\t0\ta.txt\0" + "0\t7\tgone.txt\0"

        let files = GitChangedFile.parse(nameStatus: nameStatus, numstat: numstat)

        #expect(files == [
            GitChangedFile(path: "a.txt", status: .added, insertions: 5, deletions: 0),
            GitChangedFile(path: "b/z.swift", status: .modified, insertions: 3, deletions: 1),
            GitChangedFile(path: "gone.txt", status: .deleted, insertions: 0, deletions: 7),
        ])
    }

    @Test func aRenameKeepsItsNewPathAndRemembersTheOld() {
        let nameStatus = "R100\0old name.txt\0new name.txt\0"
        let numstat = "2\t2\t\0old name.txt\0new name.txt\0"

        let files = GitChangedFile.parse(nameStatus: nameStatus, numstat: numstat)

        #expect(files == [
            GitChangedFile(
                path: "new name.txt", previousPath: "old name.txt", status: .renamed, insertions: 2, deletions: 2
            ),
        ])
    }

    @Test func aBinaryFileCountsNoLines() {
        let files = GitChangedFile.parse(nameStatus: "M\0logo.png\0", numstat: "-\t-\tlogo.png\0")
        #expect(files == [GitChangedFile(path: "logo.png", status: .modified)])
    }

    @Test func noOutputIsNoFiles() {
        #expect(GitChangedFile.parse(nameStatus: "", numstat: "").isEmpty)
    }

    @Test func refsAreSortedNewestFirstAndSkipARemoteHead() {
        let output = """
            refs/heads/main\u{0}100
            refs/remotes/origin/HEAD\u{0}300
            refs/remotes/origin/main\u{0}200
            refs/tags/v1\u{0}50
            """

        let refs = GitRef.parse(output)

        #expect(refs.map(\.name) == ["origin/main", "main", "v1"])
        #expect(refs.map(\.kind) == [.remoteBranch, .branch, .tag])
    }

    @Test func commitsKeepASubjectThatHoldsSeparators() {
        let sha = String(repeating: "a", count: 40)
        let commits = GitCommit.parse("\(sha)\u{0}42\u{0}fix: a\tb")

        #expect(commits == [GitCommit(sha: sha, subject: "fix: a\tb", date: Date(timeIntervalSince1970: 42))])
        #expect(commits.first?.shortSHA == "aaaaaaa")
    }
}
