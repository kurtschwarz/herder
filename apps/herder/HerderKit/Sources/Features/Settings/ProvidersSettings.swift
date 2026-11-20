import Core
import DesignSystem
import SwiftUI

/// The services Herder itself calls, as opposed to the agents it runs. Only
/// Anthropic so far: the model that names a New order.
struct ProvidersSettings: View {
    let naming: NamingSettings

    var body: some View {
        SettingsPaneContent(pane: .providers) {
            AnthropicSection(naming: naming)
        }
    }
}

/// Where calls to Claude go. Any Anthropic-compatible base URL works; Meridian's
/// local API is the default, and needs no key.
private struct AnthropicSection: View {
    let naming: NamingSettings

    var body: some View {
        SettingsSection("Claude / Anthropic") {
            field("API endpoint") {
                TextField(NamingConfiguration.defaultEndpoint, text: Binding(
                    get: { naming.endpoint },
                    set: { naming.setEndpoint($0) }
                ))
                .autocorrectionDisabled()
            }
            field("API key") {
                SecureField("Optional, kept in the Keychain", text: Binding(
                    get: { naming.apiKey },
                    set: { naming.setAPIKey($0) }
                ))
            }
            if let error = naming.keyError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.danger)
            }
        }
    }

    private func field(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: Theme.Spacing.normal) {
            Text(title)
                .foregroundStyle(Theme.Palette.text)
                .frame(width: 100, alignment: .leading)
            content()
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.Palette.text)
                .padding(.horizontal, Theme.Spacing.normal)
                .frame(height: Theme.Size.control)
                .fieldSurface()
        }
    }
}
