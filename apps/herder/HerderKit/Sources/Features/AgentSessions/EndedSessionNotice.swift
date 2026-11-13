/// What the banner over a session that is only being read says.
enum EndedSessionNotice: Equatable {
    /// The worktree it ran in is still there.
    case worktreeKept
    /// It is gone, so the session was opened in another worktree, named here.
    case worktreeRemoved(agent: String, carriedOnIn: String)
}
