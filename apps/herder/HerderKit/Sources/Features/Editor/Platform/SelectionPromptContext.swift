import Core

/// What the selection prompt needs to know about the world around the
/// buffer, handed to it by the view each time the pane updates.
struct SelectionPromptContext {
    let file: PathKey
    let worktree: Workspace?

    /// The buffer holds edits the disk does not, so line numbers read off the
    /// file would be wrong.
    let isUnsaved: Bool

    let sessions: WindowAgentSessions?
    let send: SendToAgentSessionAction
    let show: ShowAgentSessionAction
    let start: StartAgentSessionAction
}
