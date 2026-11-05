import Core
import DesignSystem
import RepositoriesFeature
import SwiftUI

/// Leading pane: the window's own header over the repository list. Internal: only
/// `AppFeature` uses it.
struct Sidebar: View {
    let model: RepositoriesModel
    let store: RepositoryStore

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader()
            RepositoriesView(model: model, store: store)
        }
        // The empty list has nothing tall in it, and the pane would shrink to
        // fit; the pane's height is the window's, not its content's.
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Header strip. The leading side is deliberately empty: the window hides its
/// title bar, so macOS draws the traffic lights over that space.
private struct SidebarHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            WolfMark()
        }
        .frame(height: Theme.Size.titleBar)
        .padding(.horizontal, Theme.Spacing.paneInset)
    }
}

#if DEBUG
#Preview {
    let environment = AppEnvironment.preview
    Sidebar(model: environment.repositoryList, store: environment.repositories)
        .frame(width: Theme.Size.sidebarWidth, height: 420)
        .glassPaneBackground()
        .padding(Theme.Spacing.windowPadding)
        .background(Theme.Palette.window)
}
#endif
