import Core
import DesignSystem
import SwiftUI

/// The GitHub connection: signed out, waiting for the code to be entered,
/// connected, or needing to be reconnected.
struct GitHubSection: View {
    let github: GitHubConnection

    var body: some View {
        SettingsSection("GitHub") {
            switch github.state {
            case .checking:
                row("Status", "Checking…")

            case .notConnected:
                row("Status", "Not connected")
                button("Sign in with GitHub", style: .primary) { await github.signIn() }

            case .signingIn(let code):
                row("Status", "Waiting for you on GitHub")
                Text("Enter this code at github.com/login/device.")
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .padding(.top, Theme.Spacing.tight)
                Text(code.userCode)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.Palette.text)
                    .textSelection(.enabled)
                    .padding(.vertical, Theme.Spacing.tight)
                HStack(spacing: Theme.Spacing.normal) {
                    Link("Open github.com/login/device", destination: code.verificationURL)
                        .foregroundStyle(Theme.Palette.accent)
                    Spacer(minLength: 0)
                    Button("Cancel") { github.cancelSignIn() }
                        .buttonStyle(.secondary)
                }

            case .connected(let login):
                row("Status", "Connected as @\(login)")
                button("Sign Out", style: .secondary) { await github.signOut() }

            case .unverified(let reason):
                row("Status", "Signed in, but not confirmed")
                row("Reason", reason)
                HStack(spacing: Theme.Spacing.normal) {
                    Button("Check Again") { Task { await github.recheck() } }
                        .buttonStyle(.secondary)
                    Button("Sign Out") { Task { await github.signOut() } }
                        .buttonStyle(.secondary)
                }
                .padding(.top, Theme.Spacing.tight)

            case .reconnect:
                row("Status", "Sign-in expired")
                button("Reconnect GitHub", style: .primary) { await github.signIn() }
            }

            if let error = github.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.tight)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.loose) {
            Text(label)
                .foregroundStyle(Theme.Palette.text)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.Palette.secondaryText)
                .textSelection(.enabled)
        }
        .padding(.vertical, Theme.Spacing.tight)
    }

    private func button<Style: ButtonStyle>(
        _ title: String, style: Style, action: @escaping () async -> Void
    ) -> some View {
        Button(title) { Task { await action() } }
            .buttonStyle(style)
            .padding(.top, Theme.Spacing.tight)
    }
}
