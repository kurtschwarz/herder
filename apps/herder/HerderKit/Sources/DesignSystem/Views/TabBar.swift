import Core
import SwiftUI

/// The strip over a pane: a tab for each of its `tabs`, a control for another,
/// and whatever the pane puts on the right.
///
/// One view because the editor, the terminal panel and the agent panel all have
/// tabs, and they should look and behave the same. A click shows a tab, its
/// menu pins it or, where it can be named, names it, and a drag moves it.
/// Pinned tabs sit together at the front with no close button, and a drag
/// keeps a tab on its own side of them: see ``TabOrder``.
///
/// A strip that scrolls rather than tabs that shrink: shrinking makes every
/// tab unreadable to fit one more. The tab showing is scrolled into view.
///
/// The strip is not reordered while a tab moves: ``TabDragState`` is a draft
/// of where everything would go, and `move` is called once, on release.
/// Letting go well outside the bar, or the tabs changing underneath the drag,
/// puts everything back.
public struct TabBar<Tab: Identifiable, Menu: View, NewTab: View, Trailing: View>: View {
    private let tabs: [Tab]
    private let activeID: Tab.ID?
    private let label: (Tab) -> TabBarLabel
    private let select: (Tab) -> Void
    private let close: (Tab) -> Void
    private let move: (Tab, Int) -> Void
    private let togglePin: (Tab) -> Void
    private let rename: ((Tab, String) -> Void)?
    private let openTab: (() -> Void)?
    private let menu: (Tab) -> Menu
    private let newTab: NewTab
    private let trailing: Trailing

    private static var space: String { "TabBar" }

    @State private var tabsWidth: CGFloat = 0
    @State private var barSize: CGSize = .zero
    @State private var drag: TabDragState<Tab.ID>?
    @State private var cancelled = false
    @State private var widths: [Tab.ID: CGFloat] = [:]
    @State private var viewport: CGSize = .zero
    @State private var scrollX: CGFloat = 0
    @State private var startScrollX: CGFloat = 0
    @State private var pointer: CGFloat = 0
    @State private var edgeID: Tab.ID?

    /// - Parameters:
    ///   - move: Puts a tab at an index among `tabs`, once a drag ends.
    ///   - rename: Names a tab. `nil` where tabs cannot be named.
    ///   - openTab: What a double-click on the empty space does. `nil` for
    ///     nothing, which leaves it to the window.
    ///   - menu: Items for a tab's menu, after Rename and Pin.
    ///   - newTab: The control after the last tab.
    ///   - trailing: What goes on the right.
    public init(
        tabs: [Tab],
        activeID: Tab.ID?,
        label: @escaping (Tab) -> TabBarLabel,
        select: @escaping (Tab) -> Void,
        close: @escaping (Tab) -> Void,
        move: @escaping (Tab, Int) -> Void,
        togglePin: @escaping (Tab) -> Void,
        rename: ((Tab, String) -> Void)? = nil,
        openTab: (() -> Void)? = nil,
        @ViewBuilder menu: @escaping (Tab) -> Menu,
        @ViewBuilder newTab: () -> NewTab,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.tabs = tabs
        self.activeID = activeID
        self.label = label
        self.select = select
        self.close = close
        self.move = move
        self.togglePin = togglePin
        self.rename = rename
        self.openTab = openTab
        self.menu = menu
        self.newTab = newTab()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            strip
                // No wider than the tabs, so the space past them is the
                // filler's below, and first to the room, so the tabs scroll
                // only once that is down to its minimum.
                .frame(maxWidth: tabsWidth)
                .layoutPriority(1)

            newTab

            filler
                .frame(minWidth: Theme.Spacing.loose, maxWidth: .infinity)
                .frame(height: Theme.Size.iconButton)

            trailing
        }
        .padding(.trailing, Theme.Spacing.normal)
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { barSize = $0 }
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.tight) {
                    ForEach(tabs) { tab in
                        let isLifted = drag?.dragged == tab.id
                        let shift = drag?.offset(for: tab.id) ?? 0
                        TabBarTab(
                            label: label(tab),
                            isActive: tab.id == activeID,
                            isLifted: isLifted,
                            select: { select(tab) },
                            rename: rename.map { rename in { rename(tab, $0) } },
                            togglePin: { togglePin(tab) },
                            close: { close(tab) },
                            menu: menu(tab)
                        )
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { widths[tab.id] = $0 }
                        .offset(x: shift)
                        // The tab in hand follows the pointer; the rest spring.
                        .animation(isLifted ? nil : .interactiveSpring, value: shift)
                        .zIndex(isLifted ? 1 : 0)
                        // Alongside the button's own click, which a drag under
                        // four points never disturbs.
                        .simultaneousGesture(dragGesture(for: tab, proxy: proxy))
                        .id(tab.id)
                    }
                }
                // Inside the scroll view, so the lifted tab's shadow has room.
                .padding(.leading, Theme.Spacing.normal)
                .padding(.vertical, Theme.Spacing.tight)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { tabsWidth = $0 }
            }
            .scrollIndicators(.hidden)
            // The bar scrolls itself while a tab is held, at the edges.
            .scrollDisabled(drag != nil)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
                scrollX = x
                refresh()
            }
            .onChange(of: activeID, initial: true) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
            // A closed or renamed tab can be the one the drag is holding.
            .onChange(of: tabs.map(\.id)) {
                guard drag != nil else { return }
                cancelled = true
                withAnimation(.interactiveSpring) { drag = nil }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Empty space is a place to double-click for another tab, as it is in a
    /// browser's tab strip, where there is something to open.
    @ViewBuilder
    private var filler: some View {
        if let openTab {
            DoubleClickSurface(action: openTab)
        } else {
            Color.clear
        }
    }

    private func dragGesture(for tab: Tab, proxy: ScrollViewProxy) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard !cancelled else { return }
                if drag == nil {
                    let run = tabs.firstIndex { $0.id == tab.id }.map {
                        TabOrder.run(of: $0, in: tabs) { label($0).isPinned }
                    }
                    drag = TabDragState(
                        dragging: tab.id,
                        in: tabs.map(\.id),
                        widths: widths,
                        spacing: Theme.Spacing.tight,
                        within: run
                    )
                    startScrollX = scrollX
                }
                guard drag?.dragged == tab.id else { return }
                pointer = value.translation.width
                refresh()
                scrollToEdge(at: value.location.x, proxy: proxy)
            }
            .onEnded { value in
                defer { cancelled = false }
                guard let drag, !cancelled else { return }
                let area = CGRect(origin: .zero, size: barSize).insetBy(dx: -48, dy: -24)
                withAnimation(.interactiveSpring) {
                    if area.contains(value.location), let held = tabs.first(where: { $0.id == drag.dragged }) {
                        move(held, drag.targetIndex)
                    }
                    self.drag = nil
                }
                edgeID = nil
            }
    }

    /// The pointer's travel, plus however far the strip has scrolled under it.
    private func refresh() {
        drag?.translation = pointer + scrollX - startScrollX
    }

    private func scrollToEdge(at x: CGFloat, proxy: ScrollViewProxy) {
        guard let edge = drag?.edgeScrollTarget(pointerX: x, viewport: viewport.width) else {
            edgeID = nil
            return
        }
        guard edge.id != edgeID else { return }
        edgeID = edge.id
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(edge.id, anchor: edge.leading ? .leading : .trailing)
        }
    }
}

extension TabBar where Menu == EmptyView, Trailing == EmptyView {
    /// A bar with nothing on the right, whose tabs' menus have only what
    /// every tab's has.
    public init(
        tabs: [Tab],
        activeID: Tab.ID?,
        label: @escaping (Tab) -> TabBarLabel,
        select: @escaping (Tab) -> Void,
        close: @escaping (Tab) -> Void,
        move: @escaping (Tab, Int) -> Void,
        togglePin: @escaping (Tab) -> Void,
        rename: ((Tab, String) -> Void)? = nil,
        openTab: (() -> Void)? = nil,
        @ViewBuilder newTab: () -> NewTab
    ) {
        self.init(
            tabs: tabs, activeID: activeID, label: label, select: select, close: close, move: move,
            togglePin: togglePin, rename: rename, openTab: openTab,
            menu: { _ in EmptyView() }, newTab: newTab, trailing: { EmptyView() }
        )
    }
}

extension TabBar where Menu == EmptyView, NewTab == EmptyView, Trailing == EmptyView {
    /// A bar of tabs alone.
    public init(
        tabs: [Tab],
        activeID: Tab.ID?,
        label: @escaping (Tab) -> TabBarLabel,
        select: @escaping (Tab) -> Void,
        close: @escaping (Tab) -> Void,
        move: @escaping (Tab, Int) -> Void,
        togglePin: @escaping (Tab) -> Void,
        rename: ((Tab, String) -> Void)? = nil,
        openTab: (() -> Void)? = nil
    ) {
        self.init(
            tabs: tabs, activeID: activeID, label: label, select: select, close: close, move: move,
            togglePin: togglePin, rename: rename, openTab: openTab,
            menu: { _ in EmptyView() }, newTab: { EmptyView() }, trailing: { EmptyView() }
        )
    }
}
