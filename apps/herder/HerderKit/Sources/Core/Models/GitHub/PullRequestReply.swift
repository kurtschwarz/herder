import Foundation

/// What herderd found out about the pull requests of a set of branches.
public struct PullRequestReply: Sendable, Equatable {
    /// What asking about one repository came to.
    public enum Status: Sendable, Equatable {
        case ok
        /// The GitHub App is not installed on the repository.
        case notAccessible
        /// GitHub refused the token, or herderd holds none.
        case unauthorized
        /// GitHub could not be asked. The branches are what it last said.
        case error(String)
    }

    public struct Repository: Sendable, Equatable {
        /// The `path` the query named it by.
        public var path: String
        /// `owner/name`, as `origin` names it.
        public var name: String
        public var status: Status
        /// Known once GitHub has said. It is never given a pull request, so
        /// there is no use asking about it.
        public var defaultBranch: String?
        /// Each branch asked about that GitHub has answered for, with its
        /// newest same-repository pull request, or `nil` for none.
        public var branches: [String: LinkedPullRequest?]

        public init(
            path: String,
            name: String,
            status: Status,
            defaultBranch: String? = nil,
            branches: [String: LinkedPullRequest?] = [:]
        ) {
            self.path = path
            self.name = name
            self.status = status
            self.defaultBranch = defaultBranch
            self.branches = branches
        }
    }

    /// A repository whose `origin` is not on github.com is absent.
    public var repositories: [Repository]

    /// How long herderd asks the app to wait before the next question. It
    /// grows while GitHub cannot be reached.
    public var nextPoll: Duration

    public init(repositories: [Repository], nextPoll: Duration) {
        self.repositories = repositories
        self.nextPoll = nextPoll
    }
}
