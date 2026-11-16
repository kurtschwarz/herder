/// How big a terminal is, in character cells.
public struct PTYSize: Sendable, Hashable {
    public var columns: UInt16
    public var rows: UInt16

    public init(columns: UInt16, rows: UInt16) {
        self.columns = columns
        self.rows = rows
    }
}
