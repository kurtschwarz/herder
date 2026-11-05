/// One column of git's two-letter status code: what a path has staged, or what
/// it has in the working tree and not staged.
public enum GitChange: Sendable, Equatable {
    case unchanged
    case added
    case modified
    case deleted
    case renamed
    case copied
    case typeChanged
}
