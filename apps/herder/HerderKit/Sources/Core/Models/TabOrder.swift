/// The order of a strip of tabs whose pinned tabs sit together at the front.
///
/// Every tab bar keeps the same rules: pinned tabs first, in the order they
/// were pinned, and the rest behind them. Moving a tab keeps it in its own
/// run, since a drag that pinned or unpinned a tab would do it by accident.
public enum TabOrder {
    /// The places a tab at `index` may be moved to: the pinned run if it is
    /// pinned, and the rest if it is not.
    public static func run<T>(of index: Int, in tabs: [T], isPinned: (T) -> Bool) -> ClosedRange<Int> {
        let pinned = tabs.prefix(while: isPinned).count
        return index < pinned ? 0...(pinned - 1) : pinned...(tabs.count - 1)
    }

    /// Puts the tab at `from` at `index`, held to its run. Says whether
    /// anything moved.
    @discardableResult
    public static func move<T>(_ tabs: inout [T], from: Int, to index: Int, isPinned: (T) -> Bool) -> Bool {
        guard tabs.indices.contains(from) else { return false }
        let run = run(of: from, in: tabs, isPinned: isPinned)
        let to = min(max(index, run.lowerBound), run.upperBound)
        guard to != from else { return false }
        tabs.insert(tabs.remove(at: from), at: to)
        return true
    }

    /// Moves the tab at `index` to where its pin now puts it, once it has
    /// been pinned or unpinned: to the end of the pinned run, or the start of
    /// the rest, which is where it most likely came from.
    public static func repin<T>(_ tabs: inout [T], at index: Int, isPinned: (T) -> Bool) {
        guard tabs.indices.contains(index) else { return }
        let tab = tabs.remove(at: index)
        tabs.insert(tab, at: tabs.prefix(while: isPinned).count)
    }
}
