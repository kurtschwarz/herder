import Foundation

/// One repository to ask GitHub about, and the branches to look for pull
/// requests from. `path` is the folder herderd reads `origin` from.
public struct PullRequestQuery: Sendable, Equatable {
    public var path: String
    public var branches: [String]

    public init(path: String, branches: [String]) {
        self.path = path
        self.branches = branches
    }
}
