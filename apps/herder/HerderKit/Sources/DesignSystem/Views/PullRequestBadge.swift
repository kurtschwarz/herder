import Core
import SwiftUI

/// `#123`, coloured by what the pull request is doing: green while open, grey
/// as a draft, violet once merged and red when closed without merging.
/// Clicking it opens the pull request in the browser.
public struct PullRequestBadge: View {
    private let pullRequest: LinkedPullRequest

    @Environment(\.openURL) private var openURL

    public init(_ pullRequest: LinkedPullRequest) {
        self.pullRequest = pullRequest
    }

    public var body: some View {
        let color = Self.color(for: pullRequest)
        Button { openURL(pullRequest.url) } label: {
            Text("#\(pullRequest.number)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .padding(.horizontal, Theme.Spacing.normal - 2)
                .padding(.vertical, 1)
                .background(color.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("\(Self.label(for: pullRequest)): \(pullRequest.title)")
    }

    static func color(for pullRequest: LinkedPullRequest) -> Color {
        switch pullRequest.state {
        case .open: pullRequest.isDraft ? Theme.Palette.secondaryText : Theme.Palette.success
        case .merged: Theme.Palette.violet
        case .closed: Theme.Palette.danger
        case .unknown: Theme.Palette.secondaryText
        }
    }

    static func label(for pullRequest: LinkedPullRequest) -> String {
        switch pullRequest.state {
        case .open: pullRequest.isDraft ? "Draft" : "Open"
        case .merged: "Merged"
        case .closed: "Closed"
        case .unknown: "Pull request"
        }
    }
}
