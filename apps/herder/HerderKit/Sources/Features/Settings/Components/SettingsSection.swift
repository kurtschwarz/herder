import DesignSystem
import SwiftUI

/// A titled group of rows on a field-group surface.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.normal) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.secondaryText)
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                content
            }
            .padding(Theme.Spacing.loose)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fieldGroupSurface()
        }
    }
}
