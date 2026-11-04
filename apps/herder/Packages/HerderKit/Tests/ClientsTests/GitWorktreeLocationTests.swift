import Clients
import Foundation
import Testing

@Suite struct GitWorktreeLocationTests {
    let repository = URL(filePath: "/code/api")

    @Test func aMainWorkingTreeKeepsItsWorktreesInADotFolder() {
        let path = GitWorktreeLocation.path(forBranch: "feature", inRepository: repository, kind: .mainWorkingTree)
        #expect(path == URL(filePath: "/code/api/.worktrees/feature"))
    }

    @Test func aBareRepositoryKeepsThemBesideItsOwnFiles() {
        let path = GitWorktreeLocation.path(forBranch: "feature", inRepository: repository, kind: .bare)
        #expect(path == URL(filePath: "/code/api/feature"))
    }

    @Test func slashesInTheBranchBecomeDashes() {
        let path = GitWorktreeLocation.path(forBranch: "agent/add-minimap", inRepository: repository, kind: .bare)
        #expect(path?.lastPathComponent == "agent-add-minimap")
    }

    @Test func otherFoldersHaveNoLocation() {
        #expect(GitWorktreeLocation.path(forBranch: "x", inRepository: repository, kind: .notARepository) == nil)
        #expect(GitWorktreeLocation.path(
            forBranch: "x",
            inRepository: repository,
            kind: .linkedWorktree(mainRepository: repository)
        ) == nil)
    }
}
