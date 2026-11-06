import Core
import PhosphorSwift
import SwiftUI

/// The branch a worktree is on, or the short hash it is detached at. Here
/// rather than in a feature because the status bar is not one's.
public struct CheckoutLabel: View {
    private let checkout: GitWorktree.Checkout

    public init(_ checkout: GitWorktree.Checkout) {
        self.checkout = checkout
    }

    public var body: some View {
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
}
