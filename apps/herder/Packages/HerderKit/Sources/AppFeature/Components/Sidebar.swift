import SwiftUI

/// Internal: only `AppFeature` uses it.
struct Sidebar: View {
    var body: some View {
        List {
            Label("Herd", systemImage: "square.grid.2x2")
        }
        .listStyle(.sidebar)
    }
}

#if DEBUG
#Preview {
    Sidebar()
        .frame(width: 220, height: 320)
}
#endif
