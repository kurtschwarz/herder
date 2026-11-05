import Core
import Foundation
import Testing

@Suite struct GitWorktreeLocationTests {
    let repository = URL(filePath: "/code/api")

    @Test func aMainWorkingTreeKeepsItsWorktreesInItsRoot() {
        let path = GitWorktreeLocation.path(forBranch: "feature", inRepository: repository, kind: .mainWorkingTree)
        #expect(path == URL(filePath: "/code/api/feature"))
    }

    @Test func aBareRepositoryDoesTheSame() {
        let path = GitWorktreeLocation.path(forBranch: "feature", inRepository: repository, kind: .bare)
        #expect(path == URL(filePath: "/code/api/feature"))
    }

    @Test func aSlashedBranchNests() {
        let path = GitWorktreeLocation.path(forBranch: "agent/add-minimap", inRepository: repository, kind: .bare)
        #expect(path == URL(filePath: "/code/api/agent/add-minimap"))
    }

    @Test func theTopLevelFolderIsWhatSitsInTheRepository() {
        let nested = URL(filePath: "/code/api/agent/add-minimap")
        #expect(GitWorktreeLocation.topLevelFolder(of: nested, inRepository: repository) == "agent")

        let flat = URL(filePath: "/code/api/feature")
        #expect(GitWorktreeLocation.topLevelFolder(of: flat, inRepository: repository) == "feature")
    }

    @Test func aPathOutsideTheRepositoryHasNoTopLevelFolder() {
        #expect(GitWorktreeLocation.topLevelFolder(
            of: URL(filePath: "/code/other/feature"),
            inRepository: repository
        ) == nil)
        #expect(GitWorktreeLocation.topLevelFolder(of: repository, inRepository: repository) == nil)
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
