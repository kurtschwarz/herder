import Foundation

/// What the naming call says a new order is: the kind of change, a short
/// kebab-case slug for its branch, and a title for the session.
public struct SessionName: Sendable, Equatable {
    public var type: OrderBranchType
    public var slug: String
    public var title: String

    public init(type: OrderBranchType, slug: String, title: String) {
        self.type = type
        self.slug = slug
        self.title = title
    }
}
