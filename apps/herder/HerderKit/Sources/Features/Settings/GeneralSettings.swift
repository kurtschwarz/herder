import Core
import DesignSystem
import SwiftUI

/// Settings that belong to no one feature, and which build this is.
struct GeneralSettings: View {
    let settings: UserSettingsStore
    let version: AppVersion
    let updater: (any UpdaterClient)?
    let daemon: DaemonConnection?
    let github: GitHubConnection?
    let pullRequests: LinkedPullRequests?

    var body: some View {
        SettingsPaneContent(pane: .general) {
            SettingsSection("About") {
                row("Version", version.display)
                if let commit = version.commit {
                    row("Commit", commit)
                }
            }

            if let github {
                GitHubSection(github: github, pullRequests: pullRequests)
            }

            if let daemon {
                SettingsSection("Daemon") {
                    switch daemon.status {
                    case .connecting:
                        row("Status", "Connecting…")
                    case .connected(let info):
                        row("Status", "Connected")
                        row("Version", info.daemonVersion)
                        row("Protocol", "\(info.protocolVersion)")
                    case .incompatible(let version, let supports, let app):
                        row("Status", "Incompatible")
                        row("Version", version)
                        row("Protocol", "herderd speaks \(Self.describe(supports)), this app speaks \(Self.describe(app))")
                    case .unavailable(let reason):
                        row("Status", "Unavailable")
                        row("Reason", reason)
                    }
                }
            }

            if let updater {
                SettingsSection("Updates") {
                    HStack(alignment: .center, spacing: Theme.Spacing.loose) {
                        // The settings file's, which the composition root
                        // pushes into the updater.
                        Toggle("Check for updates automatically", isOn: Binding(
                            get: { settings.settings.checkForUpdatesAutomatically },
                            set: { checks in settings.update { $0.checkForUpdatesAutomatically = checks } }
                        ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .foregroundStyle(Theme.Palette.text)
                        Spacer(minLength: 0)
                        Button("Check Now") { updater.checkForUpdates() }
                            .buttonStyle(.secondary)
                    }
                    .padding(.vertical, Theme.Spacing.tight)
                }
            }
        }
    }

    private static func describe(_ versions: ClosedRange<Int>) -> String {
        versions.lowerBound == versions.upperBound ? "\(versions.lowerBound)" : "\(versions.lowerBound)–\(versions.upperBound)"
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
}
