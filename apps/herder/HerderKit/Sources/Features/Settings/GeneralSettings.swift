import Core
import DesignSystem
import SwiftUI

/// Settings that belong to no one feature, and which build this is.
struct GeneralSettings: View {
    let version: AppVersion
    let updater: (any UpdaterClient)?

    /// A copy of the updater's setting, which it does not publish changes to.
    /// Read when the pane appears and written back on every change.
    @State private var checksAutomatically = false

    var body: some View {
        SettingsPaneContent(pane: .general) {
            SettingsSection("About") {
                row("Version", version.display)
                if let commit = version.commit {
                    row("Commit", commit)
                }
            }

            if let updater {
                SettingsSection("Updates") {
                    HStack(alignment: .center, spacing: Theme.Spacing.loose) {
                        Toggle("Check for updates automatically", isOn: $checksAutomatically)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .foregroundStyle(Theme.Palette.text)
                        Spacer(minLength: 0)
                        Button("Check Now") { updater.checkForUpdates() }
                            .buttonStyle(.secondary)
                    }
                    .padding(.vertical, Theme.Spacing.tight)
                }
                .onAppear { checksAutomatically = updater.automaticallyChecksForUpdates }
                .onChange(of: checksAutomatically) { _, checks in
                    updater.automaticallyChecksForUpdates = checks
                }
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
}
