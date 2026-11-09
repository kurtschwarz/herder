import Core
import DesignSystem
import PhosphorSwift
import SwiftUI

/// The strip over the screen: a tab for each open session, and a button for
/// another.
struct AgentHeader: View {
    let model: AgentPanelModel

    @State private var tabsWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            // Scrolls rather than squeezing: the panel is narrow, and a tab
            // squeezed to a dot says nothing.
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.tight) {
                    ForEach(model.tabs) { tab in
                        AgentTabView(
                            title: model.title(of: tab),
                            isActive: tab.id == model.activeTab?.id,
                            select: { model.select(tab) },
                            close: { model.close(tab) }
                        )
                    }
                }
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { tabsWidth = $0 }
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            // No wider than the tabs, so the space past them is the surface's
            // below, and first to the room, so the tabs scroll only once that
            // is down to its minimum.
            .frame(maxWidth: tabsWidth)
            .layoutPriority(1)

            AgentStartMenu(catalog: model.catalog, start: { agent in Task { await model.startSession(agent) } }) {
                HoverIconLabel(icon: Ph.plus.regular)
            }
            .disabled(model.workspace == nil)

            // Empty space is a place to double-click for another session, as
            // it is in a browser's tab strip.
            DoubleClickSurface(action: startAnother)
                .frame(minWidth: Theme.Spacing.loose, maxWidth: .infinity)
                .frame(height: Theme.Size.iconButton)
        }
        .padding(.horizontal, Theme.Spacing.normal)
        .padding(.vertical, Theme.Spacing.tight)
    }

    /// Another session, with the agent used last.
    private func startAnother() {
        guard model.workspace != nil else { return }
        Task { await model.startSession() }
    }
}

private struct AgentTabView: View {
    let title: String
    let isActive: Bool
    let select: () -> Void
    let close: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            PhIcon(Ph.sparkle.regular, size: 14)
                .foregroundStyle(isActive ? Theme.Palette.accent : Theme.Palette.tertiaryText)

            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(isActive ? Theme.Palette.text : Theme.Palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 160, alignment: .leading)

            HoverIconButton(icon: Ph.x.bold, iconSize: 10, side: 18, radius: 5, help: "Close Tab", action: close)
                .opacity(isActive || isHovering ? 1 : 0)
        }
        .padding(.horizontal, Theme.Spacing.normal + 2)
        .frame(height: Theme.Size.iconButton)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .fill(isActive ? Theme.Palette.control : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Close Tab", action: close)
        }
    }
}
