import Core
import DesignSystem
import SwiftUI

/// Settings that belong to no one feature, and which build this is.
struct GeneralSettings: View {
    let version: AppVersion

    var body: some View {
        SettingsPaneContent(pane: .general) {
            SettingsSection("About") {
                row("Version", version.display)
                if let commit = version.commit {
                    row("Commit", commit)
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
