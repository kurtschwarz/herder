import Core
import DesignSystem
import PhosphorSwift
import SwiftUI

/// The strip under the editor: the branch the worktree is on, and what is known
/// about the file showing. Plain text, like the breadcrumb: it reports, and
/// nothing in it is clickable.
struct EditorStatusBar: View {
    let checkout: GitWorktree.Checkout?

    /// `nil` when there is no text showing, which leaves the right side empty.
    let file: File?

    struct File: Equatable {
        let encoding: String
        let language: String
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.Palette.hairline).frame(height: 1)

            HStack(spacing: Theme.Spacing.loose) {
                if let checkout {
                    HStack(spacing: Theme.Spacing.tight + 2) {
                        PhIcon(Ph.gitBranch.regular, size: 14)
                        switch checkout {
                        case .branch(let name):
                            Text(name)
                        case .detached(let sha):
                            Text(sha).font(.system(size: 12, design: .monospaced))
                        }
                    }
                }
                Spacer(minLength: 0)
                if let file {
                    Text(file.encoding)
                    Text(file.language)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.Palette.secondaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, Theme.Spacing.paneInset)
            .padding(.vertical, Theme.Spacing.tight)
        }
    }
}
