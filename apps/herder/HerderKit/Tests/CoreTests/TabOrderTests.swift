import Testing

@testable import Core

/// Pinned tabs are the capital letters.
@Suite struct TabOrderTests {
    let isPinned: (String) -> Bool = { $0.uppercased() == $0 }

    @Test func aTabMovesWithinItsRun() {
        var tabs = ["A", "B", "c", "d", "e"]

        #expect(TabOrder.move(&tabs, from: 4, to: 2, isPinned: isPinned))
        #expect(tabs == ["A", "B", "e", "c", "d"])

        TabOrder.move(&tabs, from: 0, to: 1, isPinned: isPinned)
        #expect(tabs == ["B", "A", "e", "c", "d"])
    }

    @Test func aMoveStopsAtTheEdgeOfItsRun() {
        var tabs = ["A", "B", "c", "d"]

        TabOrder.move(&tabs, from: 3, to: 0, isPinned: isPinned)
        #expect(tabs == ["A", "B", "d", "c"])

        TabOrder.move(&tabs, from: 0, to: 9, isPinned: isPinned)
        #expect(tabs == ["B", "A", "d", "c"])
    }

    @Test func aMoveThatGoesNowhereSaysSo() {
        var tabs = ["A", "b"]

        #expect(!TabOrder.move(&tabs, from: 1, to: 0, isPinned: isPinned))
        #expect(!TabOrder.move(&tabs, from: 5, to: 0, isPinned: isPinned))
        #expect(tabs == ["A", "b"])
    }

    @Test func pinningGoesToTheEndOfThePinnedRun() {
        var tabs = ["A", "b", "c", "D"]

        TabOrder.repin(&tabs, at: 3, isPinned: isPinned)

        #expect(tabs == ["A", "D", "b", "c"])
    }

    @Test func unpinningGoesToTheStartOfTheRest() {
        // `A` has just been unpinned.
        var tabs = ["A", "B", "c"]

        TabOrder.repin(&tabs, at: 0, isPinned: { $0 == "B" })

        #expect(tabs == ["B", "A", "c"])
    }

    @Test func theRunsAreThePinnedTabsAndTheRest() {
        let tabs = ["A", "B", "c"]

        #expect(TabOrder.run(of: 1, in: tabs, isPinned: isPinned) == 0...1)
        #expect(TabOrder.run(of: 2, in: tabs, isPinned: isPinned) == 2...2)
    }
}
