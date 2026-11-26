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
            SettingsSection("Wrapping") {
                HStack(alignment: .center, spacing: Theme.Spacing.loose) {
                    Toggle("Wrap lines", isOn: Binding(
                        get: { settings.settings.wordWrap },
                        set: { wraps in settings.update { $0.wordWrap = wraps } }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .foregroundStyle(Theme.Palette.text)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Theme.Spacing.tight)
                HStack(alignment: .center, spacing: Theme.Spacing.loose) {
                    Text("Wrap at column")
                        .foregroundStyle(Theme.Palette.text)
                    Spacer(minLength: 0)
                    WrapColumnField(settings: settings)
                }
                .padding(.vertical, Theme.Spacing.tight)
                .opacity(settings.settings.wordWrap ? 1 : 0.5)
                .disabled(!settings.settings.wordWrap)
            }
        }
    }
}

/// A narrow number field for `editor.wrap_column`. Empty is no column.
///
/// Keeps what was typed apart from the setting, and only hands over a value
/// the setting accepts: typing 80 passes through 8, which is not one.
private struct WrapColumnField: View {
    let settings: UserSettingsStore

    @State private var text = ""

    var body: some View {
        TextField("Window edge", text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Theme.Palette.text)
            .padding(.horizontal, Theme.Spacing.normal)
            .frame(width: 110, height: Theme.Size.control)
            .fieldSurface()
            .onAppear { text = Self.text(for: settings.settings.wrapColumn) }
            .onChange(of: text) { _, typed in
                if Self.trimmed(typed).isEmpty {
                    settings.update { $0.wrapColumn = nil }
                } else if let column = Int(Self.trimmed(typed)), column >= UserSettings.minimumWrapColumn {
                    settings.update { $0.wrapColumn = column }
                }
            }
            .onChange(of: settings.settings.wrapColumn) { _, column in
                // An edit of the file, or a value typed that is not yet one.
                if column != Int(Self.trimmed(text)) { text = Self.text(for: column) }
            }
            .onSubmit { text = Self.text(for: settings.settings.wrapColumn) }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }

    private static func text(for column: Int?) -> String {
        column.map(String.init) ?? ""
    }
}
