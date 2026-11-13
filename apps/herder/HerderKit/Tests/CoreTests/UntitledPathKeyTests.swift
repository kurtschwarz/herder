import Foundation
import Testing

@testable import Core

@Suite @MainActor struct UntitledPathKeyTests {
    let root = PathKey(canonical: "/code/api")

    @Test func anUntitledKeyHasItsNameAndIsRecognised() {
        let key = PathKey.untitled("Untitled 2", in: root)

        #expect(key.name == "Untitled 2")
        #expect(key.isUntitled)
        #expect(key.isInside(root))
    }

    @Test func aRealPathIsNeverUntitled() {
        #expect(root.appending("Untitled").isUntitled == false)
    }

    @Test func twoWorkspacesKeepTheirOwnUntitledKeys() {
        let other = PathKey(canonical: "/code/web")

        #expect(PathKey.untitled("Untitled", in: root) != PathKey.untitled("Untitled", in: other))
    }

    @Test func relocatingADocumentKeepsItAndMergesOntoACleanOne() {
        let store = DocumentStore()
        let target = root.appending("a.txt")
        let clean = store.open(target, baseline: "one")
        let untitled = store.open(.untitled("Untitled", in: root), baseline: "")

        let result = store.relocate(untitled, to: target)

        #expect(result.moved.first === untitled)
        #expect(result.collapsed.first === clean)
        #expect(store.documents.count == 1)
        #expect(untitled.key == target)
    }

    @Test func aCleanDocumentRelocatedOntoADirtyOneCollapsesIntoIt() {
        let store = DocumentStore()
        let target = root.appending("a.txt")
        let dirty = store.open(target, baseline: "one")
        dirty.bufferChanged(to: "edited")
        let untitled = store.open(.untitled("Untitled", in: root), baseline: "")

        let result = store.relocate(untitled, to: target)

        #expect(result.collapsed.first === untitled)
        #expect(store.documents.count == 1)
        #expect(store.documents.first === dirty)
    }
}
