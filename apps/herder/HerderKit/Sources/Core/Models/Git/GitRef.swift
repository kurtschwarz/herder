import Foundation

/// A branch or tag a diff base can name, with when its tip was committed.
public struct GitRef: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case branch
        case remoteBranch
        case tag
    }

    /// The short name: `main`, `origin/main`, `v1.2`.
    public var name: String
    public var kind: Kind
    public var date: Date

    public init(name: String, kind: Kind, date: Date) {
        self.name = name
        self.kind = kind
        self.date = date
    }
}
