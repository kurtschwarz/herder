import Core
import DesignSystem
import PhosphorSwift
import SwiftUI

/// The open files, above the breadcrumb.
///
/// A strip that scrolls rather than tabs that shrink: shrinking makes every tab
/// unreadable to fit one more. There is no cap and no overflow menu — the tab
/// showing is scrolled into view instead.
///
/// A tab can be dragged to a new place. The strip is not reordered while it
/// moves: ``TabDragState`` is a draft of where everything would go, and the
/// model is told once, on release. Letting go outside the strip, or the tabs
/// changing underneath the drag, puts everything back.
struct EditorTabBar: View {
    let model: EditorModel

    private static let space = "EditorTabBar"

    @State private var drag: TabDragState?
    @State private var cancelled = false
    @State private var widths: [PathKey: CGFloat] = [:]
    @State private var viewport: CGSize = .zero
    @State private var scrollX: CGFloat = 0
    @State private var startScrollX: CGFloat = 0
    @State private var pointer: CGFloat = 0
    @State private var edgeKey: PathKey?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.tight) {
                    ForEach(model.openTabs) { tab in
                        let isLifted = drag?.dragged == tab.key
                        let shift = drag?.offset(for: tab.key) ?? 0
                        EditorTabView(
                            tab: tab,
                            isActive: tab.key == model.activeTab,
                            // Only the tab showing has been read, so it is the
                            // only one that can be known to have gone.
                            isDeleted: tab.key == model.activeTab && model.isDeleted,
                            isDirty: model.isDirty(tab.key),
                            isLifted: isLifted,
                            activate: { Task { await model.activate(tab.key) } },
                            close: { Task { await model.close(tab: tab.key) } }
                        )
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { widths[tab.key] = $0 }
                        .offset(x: shift)
                        // The tab in hand follows the pointer; the rest spring.
                        .animation(isLifted ? nil : .interactiveSpring, value: shift)
                        .zIndex(isLifted ? 1 : 0)
                        // Alongside the button's own click, which a drag under
                        // four points never disturbs.
                        .simultaneousGesture(dragGesture(for: tab.key, proxy: proxy))
                        .id(tab.key)
                    }
                }
                .padding(.horizontal, Theme.Spacing.normal)
                .padding(.vertical, Theme.Spacing.tight)
            }
            // The bar scrolls itself while a tab is held, at the edges.
            .scrollDisabled(drag != nil)
            .coordinateSpace(.named(Self.space))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
                scrollX = x
                refresh()
            }
            .onChange(of: model.activeTab, initial: true) { _, key in
                guard let key else { return }
                withAnimation { proxy.scrollTo(key, anchor: .center) }
            }
            // A rename or a closed tab changes the key the drag is holding.
            .onChange(of: model.tabs) {
                guard drag != nil else { return }
                cancelled = true
                withAnimation(.interactiveSpring) { drag = nil }
            }
        }
    }

    private func dragGesture(for key: PathKey, proxy: ScrollViewProxy) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard !cancelled else { return }
                if drag == nil {
                    drag = TabDragState(
                        dragging: key,
                        in: model.tabs,
                        widths: widths,
                        spacing: Theme.Spacing.tight
                    )
                    startScrollX = scrollX
                }
                guard drag?.dragged == key else { return }
                pointer = value.translation.width
                refresh()
                scrollToEdge(at: value.location.x, proxy: proxy)
            }
            .onEnded { value in
                defer { cancelled = false }
                guard let drag, !cancelled else { return }
                let strip = CGRect(origin: .zero, size: viewport).insetBy(dx: -48, dy: -24)
                withAnimation(.interactiveSpring) {
                    if strip.contains(value.location) { model.move(drag.dragged, to: drag.targetIndex) }
                    self.drag = nil
                }
                edgeKey = nil
            }
    }

    /// The pointer's travel, plus however far the strip has scrolled under it.
    private func refresh() {
        drag?.translation = pointer + scrollX - startScrollX
    }

    private func scrollToEdge(at x: CGFloat, proxy: ScrollViewProxy) {
        guard let edge = drag?.edgeScrollTarget(pointerX: x, viewport: viewport.width) else {
            edgeKey = nil
            return
        }
        guard edge.key != edgeKey else { return }
        edgeKey = edge.key
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(edge.key, anchor: edge.leading ? .leading : .trailing)
        }
    }
}

/// One tab: the file's glyph, its name, and a close button.
private struct EditorTabView: View {
    let tab: EditorTab
    let isActive: Bool
    let isDeleted: Bool
    /// Has edits that are not on disk.
    let isDirty: Bool
    /// Picked up and being dragged along the strip.
    let isLifted: Bool
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
                    .shadow(
                        color: isLifted ? Theme.Shadow.liftColor : .clear,
                        radius: Theme.Shadow.liftRadius,
                        y: Theme.Shadow.liftOffset
                    )
            }
            // The whole tab, not just where there happens to be a glyph.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            // Gone from the tab in hand, so a drag that ends on it cannot be
            // taken for a close.
            Group {
                // Unsaved edits: a dot where the close button is, until the
                // pointer is over the tab.
                if isDirty && !isHovering {
                    Circle()
                        .fill(Theme.Palette.secondaryText)
                        .frame(width: Theme.Size.unsavedDot, height: Theme.Size.unsavedDot)
                        .frame(width: Theme.Size.chevron, height: Theme.Size.chevron)
                        .help("Unsaved Changes")
                } else {
                    CloseTabButton(action: close)
                }
            }
            .padding(.trailing, Theme.Spacing.normal)
            .opacity(isLifted ? 0 : 1)
            .allowsHitTesting(!isLifted)
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
        if isActive || isLifted { return Theme.Palette.control }
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
            ForEach(["ContentView.swift", "FileTreeView.swift", "EditorState.swift", "TabDragState.swift"], id: \.self) { name in
                EditorTabView(
                    tab: EditorTab(key: PathKey(canonical: "/code/api/" + name), name: name, folder: nil),
                    isActive: name.hasPrefix("Content"),
                    isDeleted: false,
                    isDirty: name.hasPrefix("Editor"),
                    isLifted: name.hasPrefix("TabDrag"),
                    activate: {},
                    close: {}
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.normal)
    }
}
#endif
