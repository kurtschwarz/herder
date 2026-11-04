import Clients
import DesignSystem
import SwiftUI

struct WorktreeRow: View {
    let worktree: GitWorktree

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.violet)

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
        .padding(.leading, Theme.Spacing.normal)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(isHovering ? Theme.Palette.control : .clear)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help(worktree.path.path(percentEncoded: false))
    }
}
