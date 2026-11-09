import Core
import SwiftUI

extension EnvironmentValues {
    /// How a feature asks this window to show a different workspace. See
    /// ``OpenWorkspaceAction``, which is in `Core` with the rest of the
    /// workspace vocabulary.
    ///
    /// The key is here rather than in `Core` because `Core` may not import
    /// SwiftUI, and here rather than in a feature because the App target has to
    /// set what a feature reads — and App importing one feature to configure
    /// another would be the coupling the rule against it exists to stop.
    /// `DesignSystem` is the one module every feature already has that can
    /// import SwiftUI.
    ///
    /// Defaults to doing nothing, so a feature rendered without a window around
    /// it — a preview, a test — still builds and still draws.
    @Entry public var openWorkspace: OpenWorkspaceAction = .inert

    /// How a feature asks this window to start an agent session in a worktree.
    /// See ``StartAgentSessionAction``; carried here for the reason above.
    @Entry public var startAgentSession: StartAgentSessionAction = .inert

    /// How a feature asks this window to bring an open agent session forward.
    /// See ``ShowAgentSessionAction``; carried here for the reason above.
    @Entry public var showAgentSession: ShowAgentSessionAction = .inert

    /// How a feature asks this window to pick up an agent session from the
    /// history. See ``ResumeAgentSessionAction``; carried here for the reason
    /// above.
    @Entry public var resumeAgentSession: ResumeAgentSessionAction = .inert

    /// How a feature asks this window to name an open agent session. See
    /// ``RenameAgentSessionAction``; carried here for the reason above.
    @Entry public var renameAgentSession: RenameAgentSessionAction = .inert
}
