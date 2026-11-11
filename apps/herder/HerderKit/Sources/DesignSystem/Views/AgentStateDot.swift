import Core
import SwiftUI

/// The dot that says what an agent session is doing. Here because the sidebar's
/// list and the agent panel's header must colour it the same way.
public struct AgentStateDot: View {
    private let state: AgentSession.State

    public init(_ state: AgentSession.State) {
        self.state = state
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch state {
        case .working: Theme.Palette.success
        case .needsInput: Theme.Palette.warning
        case .exited(let code) where code != 0: Theme.Palette.danger
        case .failed: Theme.Palette.danger
        case .paused, .starting, .idle, .exited: Theme.Palette.tertiaryText
        }
    }
}
