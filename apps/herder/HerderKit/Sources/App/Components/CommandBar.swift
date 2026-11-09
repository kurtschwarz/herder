import DesignSystem
import PhosphorSwift
import SwiftUI

/// The bar across the top of the panes beside the sidebar, where searching
/// files, running commands and jumping to agents will go.
///
/// A placeholder: it draws the bar and does nothing yet. It sits in the band
/// the window treats as its title bar, so it moves the window when dragged
/// and zooms it on a double-click, like the sidebar's header beside it.
/// Internal: only `AppFeature` uses it.
struct CommandBar: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            PhIcon(Ph.magnifyingGlass.regular, size: 16)
                .foregroundStyle(Theme.Palette.secondaryText)

            Text("Search files, run commands, jump to agents\u{2026}")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)

            Spacer(minLength: Theme.Spacing.normal)

            Text("\u{2318}K")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Palette.secondaryText)
                .padding(.horizontal, Theme.Spacing.normal)
                .frame(height: Theme.Size.keycap)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.Palette.control)
                )
        }
        .padding(.leading, Theme.Spacing.paneInset)
        .padding(.trailing, Theme.Spacing.normal)
        .frame(maxWidth: .infinity)
        .frame(height: Theme.Size.commandBar)
        .glassPaneBackground()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Command palette")
    }
}

#if DEBUG
#Preview {
    CommandBar()
        .frame(width: 900)
        .padding(Theme.Spacing.windowPadding)
        .background(Theme.Palette.window)
}
#endif
