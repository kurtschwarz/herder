import Foundation

/// What a new order is for, which is the first part of its branch name. The
/// only types Herder names a branch with.
public enum OrderBranchType: String, Codable, Sendable, Equatable {
    case feat
    case fix
    case chore
}
