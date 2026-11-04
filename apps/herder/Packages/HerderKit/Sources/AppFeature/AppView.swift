import DesignSystem
import SwiftUI

/// Root view. Owns navigation and composes features; holds no feature logic.
public struct AppView: View {
    @State private var model: AppModel

    public init(model: AppModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            VStack(spacing: Theme.Spacing.normal) {
                Image(systemName: "dog")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.Palette.accent)
                Text("Herder")
                    .font(.title2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#if DEBUG
#Preview {
    AppView(model: AppModel(files: PreviewFileClient()))
        .frame(width: 900, height: 560)
}
#endif
