import Core
import Foundation
import TestSupport
import Testing

@testable import FileTreeFeature

@Suite struct FileTreeModelTests {
    let files = InMemoryFileClient()
    let git = StubGitClient()
    let watcher = StubFileWatcherClient()
    let clock = VirtualClockClient()
    let state = InMemoryStateStore()
    let model: FileTreeModel
    let root = URL(filePath: "/code/api")

    /// Stands in for the window showing this worktree. Since 4g a workspace
    /// drains only while something is displaying it, so a suite driving the
    /// watcher has to say what is on screen or it would watch nothing happen.
    let window = NSObject()

    init() {
        let registry = WorkspaceRegistry(
            files: files,
            git: git,
            watcher: watcher,
            clock: clock,
            state: state
        )
        registry.display(WorkspaceID(root), from: window)
        model = FileTreeModel(store: registry)
    }

    func dir(_ name: String, in parent: URL? = nil) -> DirectoryEntry {
        DirectoryEntry(url: (parent ?? root).appending(path: name), isDirectory: true)
    }

    func file(_ name: String, in parent: URL? = nil) -> DirectoryEntry {
        DirectoryEntry(url: (parent ?? root).appending(path: name), isDirectory: false)
    }

    func names(_ model: FileTreeModel) -> [String] {
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

        #expect(model.listing(of: secret.url) == .unreadable)
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

    @Test func movingToTheTrashRemovesTheRowAtOnce() async {
        let a = file("a.txt")
        files.seed(children: [a, file("b.txt")], of: root)
        await model.setRoot(root)

        await model.requestDelete(a, permanently: false)

        #expect(names(model) == ["b.txt"])
        #expect(files.deletions == [.init(url: a.url, permanently: false)])
        #expect(model.pendingDelete == nil)
    }

    @Test func deletingForGoodAsksFirstAndTouchesNothingUntilConfirmed() async {
        let a = file("a.txt")
        files.seed(children: [a], of: root)
        await model.setRoot(root)

        await model.requestDelete(a, permanently: true)

        #expect(model.pendingDelete == a)
        #expect(files.deletions.isEmpty)
        #expect(names(model) == ["a.txt"])

        await model.confirmDelete(a)

        #expect(model.pendingDelete == nil)
        #expect(files.deletions == [.init(url: a.url, permanently: true)])
        #expect(names(model).isEmpty)
    }

    @Test func cancellingTheQuestionDeletesNothing() async {
        let a = file("a.txt")
        files.seed(children: [a], of: root)
        await model.setRoot(root)
        await model.requestDelete(a, permanently: true)

        model.cancelDelete()

        #expect(model.pendingDelete == nil)
        #expect(files.deletions.isEmpty)
    }

    @Test func deletingTheSelectedFileDoesNotSelectAnotherInItsPlace() async {
        let b = file("b.txt")
        files.seed(children: [file("a.txt"), b, file("c.txt")], of: root)
        await model.setRoot(root)
        model.select(b.url)

        await model.requestDelete(b, permanently: false)

        #expect(model.selected == nil)
    }

    @Test func deletingAnotherFileKeepsTheSelection() async {
        let a = file("a.txt")
        files.seed(children: [a, file("b.txt")], of: root)
        await model.setRoot(root)
        model.select(a.url)

        await model.requestDelete(file("b.txt"), permanently: false)

        #expect(model.selected == a.url)
    }

    @Test func deletingAFolderForgetsWhatWasOpenInsideIt() async {
        let sources = dir("Sources")
        let nested = dir("Nested", in: sources.url)
        let inside = file("App.swift", in: nested.url)
        files.seed(children: [sources, file("a.txt")], of: root)
        files.seed(children: [nested], of: sources.url)
        files.seed(children: [inside], of: nested.url)
        await model.setRoot(root)
        await model.toggle(sources.url)
        await model.toggle(nested.url)
        model.select(inside.url)

        await model.requestDelete(sources, permanently: false)

        #expect(names(model) == ["a.txt"])
        #expect(!model.isExpanded(sources.url))
        #expect(!model.isExpanded(nested.url))
        #expect(!model.canCollapse)
        #expect(model.selected == inside.url)
    }

    @Test func aRefusalFromTheDiskLeavesTheTreeAsItWas() async {
        let ghost = file("ghost.txt")
        files.seed(children: [file("a.txt")], of: root)
        await model.setRoot(root)

        await model.requestDelete(ghost, permanently: false)

        #expect(names(model) == ["a.txt"])
        #expect(files.deletions.isEmpty)
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

    func ignoredNames(_ model: FileTreeModel) -> [String] {
        model.rows.compactMap {
            if case .entry(let entry) = $0.kind, $0.isIgnored { entry.name } else { nil }
        }
    }

    @Test func anIgnoredEntryIsFlagged() async {
        files.seed(children: [file("a.txt"), file("debug.log")], of: root)
        git.seed(ignored: ["debug.log"], in: root)

        await model.setRoot(root)

        #expect(ignoredNames(model) == ["debug.log"])
    }

    @Test func everythingInsideAnIgnoredFolderIsIgnoredWithIt() async {
        let build = dir("build")
        files.seed(children: [build, file("a.txt")], of: root)
        files.seed(children: [file("out.o", in: build.url)], of: build.url)
        git.seed(ignored: ["build"], in: root)
        await model.setRoot(root)

        await model.toggle(build.url)

        #expect(ignoredNames(model) == ["build", "out.o"])
    }

    /// One `git status` covers the whole worktree, including folders nobody has
    /// opened, so opening one asks git nothing.
    @Test func gitIsAskedOnceForTheTreeHoweverManyFoldersOpen() async {
        let build = dir("build")
        let deeper = dir("obj", in: build.url)
        let sources = dir("Sources")
        files.seed(children: [build, sources], of: root)
        files.seed(children: [deeper], of: build.url)
        files.seed(children: [file("a.o", in: deeper.url)], of: deeper.url)
        files.seed(children: [file("a.swift", in: sources.url)], of: sources.url)
        git.seed(ignored: ["build"], in: root)
        await model.setRoot(root)

        await model.toggle(build.url)
        await model.toggle(deeper.url)
        await model.toggle(sources.url)

        #expect(git.statusLookups == [root])
        #expect(ignoredNames(model) == ["build", "obj", "a.o"])
    }

    @Test func aFileIgnoredOnlyInsideAFolderFlagsOnlyThatEntry() async {
        let sources = dir("Sources")
        files.seed(children: [sources], of: root)
        files.seed(children: [file("a.swift", in: sources.url), file("b.log", in: sources.url)], of: sources.url)
        git.seed(ignored: ["Sources/b.log"], in: root)
        await model.setRoot(root)

        await model.toggle(sources.url)

        #expect(ignoredNames(model) == ["b.log"])
    }

    @Test func theListingShowsBeforeGitHasAnswered() async {
        files.seed(children: [file("a.txt"), file("debug.log")], of: root)
        git.seed(ignored: ["debug.log"], in: root)
        git.holdStatusLookups()

        let reading = Task { await model.setRoot(root) }
        while git.statusLookups.isEmpty { await Task.yield() }

        #expect(names(model) == ["a.txt", "debug.log"])
        #expect(ignoredNames(model).isEmpty)

        git.releaseStatusLookups()
        await reading.value

        #expect(ignoredNames(model) == ["debug.log"])
    }

    @Test func aFailedGitLookupKeepsTheMarksAndStillShowsTheFiles() async {
        files.seed(children: [file("debug.log")], of: root)
        git.seed(ignored: ["debug.log"], in: root)
        await model.setRoot(root)

        files.seed(children: [file("debug.log"), file("new.txt")], of: root)
        git.failStatusLookups()
        await model.refresh()

        #expect(names(model) == ["debug.log", "new.txt"])
        #expect(ignoredNames(model) == ["debug.log"])
    }

    @Test func anEntryNoLongerIgnoredLosesTheFlagOnRefresh() async {
        files.seed(children: [file("debug.log")], of: root)
        git.seed(ignored: ["debug.log"], in: root)
        await model.setRoot(root)

        git.seed(ignored: [], in: root)
        await model.refresh()

        #expect(ignoredNames(model).isEmpty)
    }

    @Test func everythingInsideAnUntrackedFolderIsUntrackedWithIt() async {
        let fresh = dir("fresh")
        files.seed(children: [fresh], of: root)
        files.seed(children: [file("a.txt", in: fresh.url)], of: fresh.url)
        git.seed(status: ["fresh": .untracked], in: root)
        await model.setRoot(root)

        await model.toggle(fresh.url)

        #expect(model.status.status(of: PathKey(fresh.url.appending(path: "a.txt"))) == .untracked)
        // Untracked is not ignored: it is the work, not the leftovers.
        #expect(ignoredNames(model).isEmpty)
    }

    func marks(_ model: FileTreeModel) -> [String: GitMark] {
        Dictionary(uniqueKeysWithValues: model.rows.compactMap { row in
            guard case .entry(let entry) = row.kind, let mark = row.mark else { return nil }
            return (entry.name, mark)
        })
    }

    @Test func aFileWearsWhatGitSaysAboutIt() async {
        files.seed(children: [file("a.txt"), file("b.txt"), file("c.txt"), file("d.log")], of: root)
        git.seed(status: [
            "a.txt": .untracked,
            "b.txt": .tracked(staged: .unchanged, unstaged: .modified),
            "c.txt": .unmerged,
            "d.log": .ignored,
        ], in: root)

        await model.setRoot(root)

        // Ignored is said with a fade, not with a letter.
        #expect(marks(model) == ["a.txt": .untracked, "b.txt": .modified, "c.txt": .unmerged])
        #expect(ignoredNames(model) == ["d.log"])
    }

    /// Staged and unstaged stay apart in the model but read as one "modified"
    /// in the tree, which has no language yet for telling them apart.
    @Test func stagedAndUnstagedBothReadAsModified() async {
        files.seed(children: [file("a.txt"), file("b.txt")], of: root)
        git.seed(status: [
            "a.txt": .tracked(staged: .added, unstaged: .unchanged),
            "b.txt": .tracked(staged: .unchanged, unstaged: .modified),
        ], in: root)

        await model.setRoot(root)

        #expect(marks(model) == ["a.txt": .modified, "b.txt": .modified])
        #expect(model.status.status(of: PathKey(file("a.txt").url))
            == .tracked(staged: .added, unstaged: .unchanged))
    }

    /// A deletion draws no row, so the mark on the folder above it is the only
    /// thing that says it happened.
    @Test func aClosedFolderWearsWhatChangedInsideIt() async {
        let sources = dir("Sources")
        files.seed(children: [sources], of: root)
        files.seed(children: [], of: sources.url)
        git.seed(status: ["Sources/Gone.swift": .tracked(staged: .deleted, unstaged: .unchanged)], in: root)
        await model.setRoot(root)

        #expect(marks(model) == ["Sources": .modified])

        // Open, and the rows inside say it better than a mark could — except
        // here there are none, which is the one case Q10 cannot rescue.
        await model.toggle(sources.url)

        #expect(marks(model).isEmpty)
    }

    @Test func aSelectionIsDroppedWhenItsFileGoesAway() async {
        files.seed(children: [file("a.txt")], of: root)
        await model.setRoot(root)
        model.select(file("a.txt").url)
        model.beginRenaming(file("a.txt").url)

        files.seed(children: [], of: root)
        watcher.change([root])
        for _ in 0..<500 { await Task.yield() }

        #expect(model.selected == nil)
        #expect(model.renaming == nil)
    }

    /// The user is part-way through typing and its path does not exist yet by
    /// definition, so nothing about the tree moving should take the field away.
    @Test func aNameFieldSurvivesTheTreeChangingUnderIt() async {
        files.seed(children: [file("a.txt")], of: root)
        await model.setRoot(root)
        await model.beginCreating(in: root, isDirectory: false)

        files.seed(children: [file("a.txt"), file("b.txt")], of: root)
        watcher.change([root])
        for _ in 0..<500 { await Task.yield() }

        #expect(model.creating != nil)
        #expect(names(model) == ["a.txt", "b.txt"])
    }

    @Test func aFileMadeInATerminalShowsUpWithoutTheWindowBeingTouched() async {
        files.seed(children: [file("a.txt")], of: root)
        await model.setRoot(root)

        files.seed(children: [file("a.txt"), file("b.txt")], of: root)
        git.seed(status: ["b.txt": .untracked], in: root)
        watcher.change([root])
        for _ in 0..<500 { await Task.yield() }

        #expect(names(model) == ["a.txt", "b.txt"])
        #expect(marks(model) == ["b.txt": .untracked])
    }

    @Test func aWorktreeRemovedUnderTheAppShowsNothing() async {
        files.seed(children: [file("a.txt")], of: root)
        await model.setRoot(root)

        watcher.vanish(root)
        for _ in 0..<500 { await Task.yield() }

        #expect(model.rows.isEmpty)
    }

    @Test func aTrackedChangeInsideAClosedFolderMarksTheFolder() async {
        let sources = dir("Sources")
        files.seed(children: [sources], of: root)
        git.seed(status: ["Sources/deep/App.swift": .tracked(staged: .unchanged, unstaged: .modified)], in: root)

        await model.setRoot(root)

        #expect(model.status.rollup(of: PathKey(sources.url)) == .modified)
        #expect(model.status.rollup(of: PathKey(root)) == .modified)
    }
}
