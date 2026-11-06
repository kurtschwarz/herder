import Core
import DesignSystem
import PhosphorSwift
import SwiftUI

/// The open files, above the breadcrumb.
///
/// A strip that scrolls rather than tabs that shrink: shrinking makes every tab
/// unreadable to fit one more. There is no cap and no overflow menu — the tab
/// showing is scrolled into view instead.
struct EditorTabBar: View {
    let model: EditorModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.tight) {
                    ForEach(model.openTabs) { tab in
                        EditorTabView(
                            tab: tab,
                            isActive: tab.key == model.activeTab,
                            // Only the tab showing has been read, so it is the
                            // only one that can be known to have gone.
                            isDeleted: tab.key == model.activeTab && model.isDeleted,
                            activate: { Task { await model.activate(tab.key) } },
                            close: { Task { await model.close(tab: tab.key) } }
                        )
                        .id(tab.key)
                    }
                }
                .padding(.horizontal, Theme.Spacing.normal)
                .padding(.vertical, Theme.Spacing.tight)
            }
            .onChange(of: model.activeTab, initial: true) { _, key in
                guard let key else { return }
                withAnimation { proxy.scrollTo(key, anchor: .center) }
            }
        }
    }
}

/// One tab: the file's glyph, its name, and a close button.
private struct EditorTabView: View {
    let tab: EditorTab
    let isActive: Bool
    let isDeleted: Bool
    let activate: () -> Void
    let close: () -> Void

    @State private var isHovering = false

    var body: some View {
        // A `Button`, not a tap gesture. A gesture inside a horizontal
        // `ScrollView` has to win against the scroll view's own recogniser,
        // and intermittently does not — which is a tab you have to click
        // three times. A button is routed through AppKit's control path and
        // does not negotiate for the click.
        Button(action: activate) {
            HStack(spacing: Theme.Spacing.normal) {
                PhIcon(Ph.file.regular, size: 14)
                    .foregroundStyle(Theme.Palette.fileIcon(forExtension: ext))

                HStack(spacing: Theme.Spacing.tight) {
                    // One weight for every tab: the colour says which is
                    // showing, and a weight that changed would resize the tab
                    // under the pointer as it was clicked.
                    Text(tab.name)
                        .font(.system(size: 13))
                        .foregroundStyle(isActive ? Theme.Palette.text : Theme.Palette.secondaryText)
                        .strikethrough(isDeleted)

                    // Two tabs called `index.ts` are the same tab otherwise.
                    if let folder = tab.folder {
                        Text(folder)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.tertiaryText)
                    }
                }
                .lineLimit(1)
                .fixedSize()
                .opacity(isDeleted ? Theme.Opacity.ignored : 1)

                // Where the close button goes. It is laid over rather than in,
                // so that a click landing beside the ✕ activates the tab
                // instead of falling into a gap between two controls.
                Color.clear.frame(width: Theme.Size.chevron, height: Theme.Size.chevron)
            }
            .padding(.horizontal, Theme.Spacing.normal)
            .frame(height: Theme.Size.iconButton)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(fill)
            }
            // The whole tab, not just where there happens to be a glyph.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            CloseTabButton(action: close)
                .padding(.trailing, Theme.Spacing.normal)
        }
        .onHover { isHovering = $0 }
        .help(tab.key.path)
    }

    private var ext: String {
        guard let dot = tab.name.lastIndex(of: "."), dot != tab.name.startIndex else { return "" }
        return tab.name[tab.name.index(after: dot)...].lowercased()
    }

    /// The tab showing sits on a surface; the rest are flat on the window.
    private var fill: Color {
        if isActive { return Theme.Palette.control }
        return isHovering ? Theme.Palette.glassTint : .clear
    }
}

/// Always visible, so there is no tab whose close button has to be hunted for
/// by hovering first.
private struct CloseTabButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            PhIcon(Ph.x.bold, size: 10)
                .foregroundStyle(isHovering ? Theme.Palette.text : Theme.Palette.tertiaryText)
                .frame(width: Theme.Size.chevron, height: Theme.Size.chevron)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(isHovering ? Theme.Palette.controlPressed : .clear)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Close Tab")
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: 0) {
        TabStripPreview()
    }
    .frame(width: 720)
    .padding(.vertical, Theme.Spacing.loose)
    .background(Theme.Palette.window)
}

/// Draws the strip from tabs alone: the real bar needs a model, and a model
/// needs a registry with files in it, which is `EditorView`'s preview.
private struct TabStripPreview: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            ForEach(["ContentView.swift", "FileTreeView.swift", "EditorState.swift"], id: \.self) { name in
                EditorTabView(
                    tab: EditorTab(key: PathKey(canonical: "/code/api/" + name), name: name, folder: nil),
                    isActive: name.hasPrefix("Content"),
                    isDeleted: false,
                    activate: {},
                    close: {}
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.normal)
    }
}
#endif
