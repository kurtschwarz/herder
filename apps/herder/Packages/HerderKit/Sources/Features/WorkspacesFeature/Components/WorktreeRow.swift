import Clients
import DesignSystem
import PhosphorSwift
import SwiftUI

struct WorktreeRow: View {
    let worktree: GitWorktree

    /// The worktree under the pointer, shared with the section so its guide
    /// line can step aside.
    @Binding var hovered: GitWorktree.ID?

    private var isHovering: Bool { hovered == worktree.id }

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            PhIcon(Ph.gitBranch.bold, size: 16)
                .foregroundStyle(Theme.Palette.secondaryText)

            switch worktree.checkout {
            case .branch(let name):
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.text)
            case .detached(let sha):
                Text(sha)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.Palette.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, Theme.Spacing.normal)
        .padding(.vertical, Theme.Spacing.tight + 2)
        // Past the guide line, landing the icon under the workspace's own:
        // the line sits mid-chevron, and the icon a chevron's width past it.
        .padding(.leading, Theme.Size.chevron / 2 - 1)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(isHovering ? Theme.Palette.control : .clear)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                hovered = worktree.id
            } else if hovered == worktree.id {
                hovered = nil
            }
        }
        .help(worktree.path.path(percentEncoded: false))
    }
}
