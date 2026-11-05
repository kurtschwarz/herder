import Clients
import ClientsTestSupport
import Foundation
import Testing

@testable import ExplorerFeature

@Suite struct ExplorerModelTests {
    let files = InMemoryFileClient()
    let model: ExplorerModel
    let root = URL(filePath: "/code/api")

    init() {
        model = ExplorerModel(files: files)
    }

    func dir(_ name: String, in parent: URL? = nil) -> DirectoryEntry {
        DirectoryEntry(url: (parent ?? root).appending(path: name), isDirectory: true)
    }

    func file(_ name: String, in parent: URL? = nil) -> DirectoryEntry {
        DirectoryEntry(url: (parent ?? root).appending(path: name), isDirectory: false)
    }

    func names(_ model: ExplorerModel) -> [String] {
        model.rows.compactMap {
            if case .entry(let entry) = $0.kind { entry.name } else { nil }
        }
    }

    @Test func theRootIsReadAndOpenStraightAway() async {
        files.seed(children: [file("README.md")], of: root)

        await model.setRoot(root)

        #expect(names(model) == ["README.md"])
    }

    @Test func foldersComeFirstThenFilesEachByNameIgnoringCase() async {
        files.seed(
            children: [file("b.txt"), dir("Tests"), file("A.txt"), dir("sources"), file(".gitignore")],
            of: root
        )

        await model.setRoot(root)

        #expect(names(model) == ["sources", "Tests", ".gitignore", "A.txt", "b.txt"])
    }

    @Test func gitsOwnFoldersAreLeftOut() async {
        files.seed(children: [dir(".git"), dir(".bare"), file(".gitignore")], of: root)

        await model.setRoot(root)

        #expect(names(model) == [".gitignore"])
    }

    @Test func aFolderIsReadTheFirstTimeItOpensAndNotAgain() async {
        let sources = dir("Sources")
        files.seed(children: [sources], of: root)
        files.seed(children: [file("App.swift", in: sources.url)], of: sources.url)
        await model.setRoot(root)

        await model.toggle(sources.url)
        await model.toggle(sources.url)
        await model.toggle(sources.url)

        #expect(files.childReads.filter { $0 == sources.url }.count == 1)
        #expect(names(model) == ["Sources", "App.swift"])
    }

    @Test func closingAFolderHidesItsChildren() async {
        let sources = dir("Sources")
        files.seed(children: [sources], of: root)
        files.seed(children: [file("App.swift", in: sources.url)], of: sources.url)
        await model.setRoot(root)

        await model.toggle(sources.url)
        await model.toggle(sources.url)

        #expect(names(model) == ["Sources"])
    }

    @Test func childrenAreOneLevelDeeper() async {
        let sources = dir("Sources")
        files.seed(children: [sources], of: root)
        files.seed(children: [file("App.swift", in: sources.url)], of: sources.url)
        await model.setRoot(root)
        await model.toggle(sources.url)

        #expect(model.rows.map(\.depth) == [0, 1])
    }

    @Test func aFolderThatCannotBeReadIsNotAnEmptyOne() async {
        let secret = dir("secret")
        files.seed(children: [secret], of: root)
        files.seedUnreadable(secret.url)
        await model.setRoot(root)

        await model.toggle(secret.url)

        #expect(model.listings[secret.url] == .unreadable)
        #expect(model.rows.last?.kind == .unreadable)
    }

    @Test func collapseAllClosesEveryFolderButKeepsTheRoot() async {
        let sources = dir("Sources")
        files.seed(children: [sources], of: root)
        files.seed(children: [], of: sources.url)
        await model.setRoot(root)
        await model.toggle(sources.url)
        #expect(model.canCollapse)

        model.collapseAll()

        #expect(!model.canCollapse)
        #expect(names(model) == ["Sources"])
    }

    @Test func aNewRootDropsWhatWasOpenAndSelected() async {
        let sources = dir("Sources")
        let other = URL(filePath: "/code/other")
        files.seed(children: [sources, file("a.txt")], of: root)
        files.seed(children: [], of: sources.url)
        files.seed(children: [], of: other)
        await model.setRoot(root)
        await model.toggle(sources.url)
        model.select(file("a.txt").url)

        await model.setRoot(other)

        #expect(model.root == other)
        #expect(!model.canCollapse)
        #expect(model.selected == nil)
        #expect(model.rows.isEmpty)
    }

    @Test func choosingTheSameRootAgainKeepsWhatIsOpen() async {
        let sources = dir("Sources")
        files.seed(children: [sources], of: root)
        files.seed(children: [], of: sources.url)
        await model.setRoot(root)
        await model.toggle(sources.url)

        await model.setRoot(root)

        #expect(model.isExpanded(sources.url))
    }

    @Test func noRootShowsNothing() async {
        files.seed(children: [file("a.txt")], of: root)
        await model.setRoot(root)
        await model.setRoot(nil)

        #expect(model.root == nil)
        #expect(model.rows.isEmpty)
    }

    @Test func refreshPicksUpFilesAddedSinceTheLastRead() async {
        files.seed(children: [file("a.txt")], of: root)
        await model.setRoot(root)

        files.seed(children: [file("a.txt"), file("b.txt")], of: root)
        await model.refresh()

        #expect(names(model) == ["a.txt", "b.txt"])
    }

    @Test func selectingAFileMarksIt() async {
        files.seed(children: [file("a.txt")], of: root)
        await model.setRoot(root)

        model.select(file("a.txt").url)

        #expect(model.selected == file("a.txt").url)
    }

    @Test func renamingMovesTheFileAndShowsTheNewName() async {
        let old = file("a.txt")
        files.seed(children: [old, file("z.txt")], of: root)
        await model.setRoot(root)
        model.beginRenaming(old.url)

        await model.commitRename(old, to: "b.txt")

        #expect(files.moves == [.init(source: old.url, destination: file("b.txt").url)])
        #expect(names(model) == ["b.txt", "z.txt"])
        #expect(model.renaming == nil)
    }

    @Test func renamingAFolderKeepsItOpen() async {
        let sources = dir("Sources")
        files.seed(children: [sources], of: root)
        files.seed(children: [file("App.swift", in: sources.url)], of: sources.url)
        await model.setRoot(root)
        await model.toggle(sources.url)

        await model.commitRename(sources, to: "Lib")

        #expect(names(model) == ["Lib", "App.swift"])
    }

    @Test func renamingTheSelectedFileKeepsItSelected() async {
        let old = file("a.txt")
        files.seed(children: [old], of: root)
        await model.setRoot(root)
        model.select(old.url)

        await model.commitRename(old, to: "b.txt")

        #expect(model.selected == file("b.txt").url)
    }

    @Test(arguments: ["", "   ", "a.txt", "x/y"])
    func aNameThatChangesNothingOrCannotBeUsedTouchesNoDisk(name: String) async {
        let old = file("a.txt")
        files.seed(children: [old], of: root)
        await model.setRoot(root)

        await model.commitRename(old, to: name)

        #expect(files.moves.isEmpty)
        #expect(names(model) == ["a.txt"])
    }

    @Test func aNameAlreadyTakenLeavesTheTreeAsItWas() async {
        let old = file("a.txt")
        files.seed(children: [old, file("b.txt")], of: root)
        await model.setRoot(root)

        await model.commitRename(old, to: "b.txt")

        #expect(names(model) == ["a.txt", "b.txt"])
        #expect(model.renaming == nil)
    }

    @Test func cancellingEndsTheEditWithoutRenaming() async {
        let old = file("a.txt")
        files.seed(children: [old], of: root)
        await model.setRoot(root)
        model.beginRenaming(old.url)

        model.cancelRenaming()

        #expect(model.renaming == nil)
        #expect(files.moves.isEmpty)
    }

    @Test func aNameFieldAppearsAtTheTopOfTheFoldersForANewFolder() async {
        files.seed(children: [dir("Sources"), file("a.txt")], of: root)
        await model.setRoot(root)

        await model.beginCreating(in: root, isDirectory: true)

        #expect(model.rows.map(\.kind) == [
            .creating(isDirectory: true), .entry(dir("Sources")), .entry(file("a.txt")),
        ])
    }

    @Test func aNameFieldAppearsAmongTheFilesForANewFile() async {
        files.seed(children: [dir("Sources"), file("a.txt")], of: root)
        await model.setRoot(root)

        await model.beginCreating(in: root, isDirectory: false)

        #expect(model.rows.map(\.kind) == [
            .entry(dir("Sources")), .creating(isDirectory: false), .entry(file("a.txt")),
        ])
    }

    @Test func creatingInAClosedFolderOpensItAndIndentsTheField() async {
        let sources = dir("Sources")
        files.seed(children: [sources], of: root)
        files.seed(children: [file("App.swift", in: sources.url)], of: sources.url)
        await model.setRoot(root)

        await model.beginCreating(in: sources.url, isDirectory: false)

        #expect(model.isExpanded(sources.url))
        #expect(model.rows.map(\.depth) == [0, 1, 1])
    }

    @Test func committingMakesTheFileAndSelectsIt() async {
        files.seed(children: [file("a.txt")], of: root)
        await model.setRoot(root)
        await model.beginCreating(in: root, isDirectory: false)

        await model.commitCreating(named: "b.txt")

        #expect(files.creations == [file("b.txt")])
        #expect(names(model) == ["a.txt", "b.txt"])
        #expect(model.selected == file("b.txt").url)
        #expect(model.creating == nil)
    }

    @Test func committingMakesTheFolder() async {
        files.seed(children: [file("a.txt")], of: root)
        await model.setRoot(root)
        await model.beginCreating(in: root, isDirectory: true)

        await model.commitCreating(named: "Lib")

        #expect(files.creations.map(\.name) == ["Lib"])
        #expect(files.creations.map(\.isDirectory) == [true])
        #expect(names(model) == ["Lib", "a.txt"])
    }

    @Test(arguments: ["", "   ", "x/y"])
    func aBlankOrUnusableNewNameMakesNothing(name: String) async {
        files.seed(children: [], of: root)
        await model.setRoot(root)
        await model.beginCreating(in: root, isDirectory: false)

        await model.commitCreating(named: name)

        #expect(files.creations.isEmpty)
        #expect(model.creating == nil)
        #expect(model.rows.isEmpty)
    }

    @Test func aNewNameAlreadyTakenMakesNothing() async {
        files.seed(children: [file("a.txt")], of: root)
        await model.setRoot(root)
        await model.beginCreating(in: root, isDirectory: false)

        await model.commitCreating(named: "a.txt")

        #expect(files.creations.isEmpty)
        #expect(names(model) == ["a.txt"])
    }

    @Test func aNameFieldCountsAsEditing() async {
        files.seed(children: [file("a.txt")], of: root)
        await model.setRoot(root)
        #expect(!model.isEditingName)

        await model.beginCreating(in: root, isDirectory: true)
        #expect(model.isEditingName)

        model.cancelCreating()
        model.beginRenaming(file("a.txt").url)
        #expect(model.isEditingName)
    }

    @Test func cancellingRemovesTheNameField() async {
        files.seed(children: [], of: root)
        await model.setRoot(root)
        await model.beginCreating(in: root, isDirectory: false)

        model.cancelCreating()

        #expect(model.rows.isEmpty)
        #expect(files.creations.isEmpty)
    }
}
