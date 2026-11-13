import Core
import DesignSystem
import SwiftUI

/// The three ways to start a session, pinned over the list: Plan and Build go
/// straight to the main worktree when one workspace is on show and ask where
/// when several are, and the plus always asks.
struct SessionLauncher: View {
    let model: RepositoriesModel

    @Environment(Workspace.self) private var active: Workspace?
    @Environment(\.startAgentSession) private var startAgentSession

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            LauncherButton(title: "Plan", icon: Ph.notepad, isDisabled: isDisabled) { start(.plan) }
                .help("Start a session in plan mode")
            LauncherButton(title: "Build", icon: Ph.hammer, isDisabled: isDisabled) { start(.build) }
                .help("Start a session")
            Button { ask(.build) } label: {
                PhIcon(Ph.plusSquare, size: 16)
            }
            .buttonStyle(.icon(size: Theme.Size.control + 4))
            .disabled(isDisabled)
            .help("New session\u{2026}")
        }
        .padding(.horizontal, Theme.Spacing.windowPadding)
        .padding(.bottom, Theme.Spacing.normal)
    }

    private var repository: Repository? {
        model.repositoryForNewSession(active: active?.id.url)
    }

    private var isDisabled: Bool { repository == nil }

    /// At once where there is one place it could go, and the modal otherwise.
    private func start(_ mode: SessionMode) {
        if let worktree = model.quickStartWorktree {
            startAgentSession(worktree, mode: mode)
        } else {
            ask(mode)
        }
    }

    private func ask(_ mode: SessionMode) {
        guard let repository else { return }
        model.beginNewSession(in: repository, active: active?.id.url, mode: mode)
    }
}

private struct LauncherButton: View {
    let title: String
    let icon: Image
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.normal) {
                PhIcon(icon, size: 14)
                Text(title)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Size.control + 4)
        }
        .buttonStyle(.secondary)
        .disabled(isDisabled)
    }
}
