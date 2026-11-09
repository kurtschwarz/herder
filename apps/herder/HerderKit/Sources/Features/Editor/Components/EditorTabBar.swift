import Core
import DesignSystem
import PhosphorSwift
import SwiftUI

/// The open files, above the breadcrumb. A file's tab is not named here:
/// renaming a file is the file tree's, and there is no new file to open.
struct EditorTabBar: View {
    let model: EditorModel

    var body: some View {
        TabBar(
            tabs: model.openTabs,
            activeID: model.activeTab,
            label: { tab in
                TabBarLabel(
                    icon: Ph.file.regular,
                    iconColor: Theme.Palette.fileIcon(forExtension: Self.ext(of: tab.name)),
                    title: tab.name,
                    // Two tabs called `index.ts` are the same tab otherwise.
                    detail: tab.folder,
                    isPinned: tab.isPinned,
                    isDirty: model.isDirty(tab.key),
                    // Only the tab showing has been read, so it is the only
                    // one that can be known to have gone.
                    isGone: tab.key == model.activeTab && model.isDeleted,
                    help: tab.key.path
                )
            },
            select: { tab in Task { await model.activate(tab.key) } },
            close: { tab in Task { await model.requestClose(tab: tab.key) } },
            move: { model.move($0.key, to: $1) },
            togglePin: { model.togglePin($0.key) }
        )
    }

    private static func ext(of name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }
}
