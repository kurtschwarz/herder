import Core
import DesignSystem
import SwiftUI

/// How the editor draws.
struct EditorSettings: View {
    let settings: UserSettingsStore

    var body: some View {
        SettingsPaneContent(pane: .editor) {
            SettingsSection("Whitespace") {
                HStack(alignment: .center, spacing: Theme.Spacing.loose) {
                    Text("Show whitespace")
                        .foregroundStyle(Theme.Palette.text)
                    Spacer(minLength: 0)
                    Picker("Show whitespace", selection: Binding(
                        get: { settings.settings.showWhitespace },
                        set: { mode in settings.update { $0.showWhitespace = mode } }
                    )) {
                        Text("None").tag(ShowWhitespace.none)
                        Text("Trailing").tag(ShowWhitespace.trailing)
                        Text("All").tag(ShowWhitespace.all)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.vertical, Theme.Spacing.tight)
            }
        }
    }
}
