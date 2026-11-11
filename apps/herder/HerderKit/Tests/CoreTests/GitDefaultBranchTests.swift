import Core
import Testing

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
