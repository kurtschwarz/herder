import AppKit
import Clients
import DesignSystem
import PhosphorSwift
import SwiftUI

/// The explorer pane's content: a header over the file tree of the selected
/// worktree.
public struct ExplorerView: View {
    private let model: ExplorerModel

    public init(model: ExplorerModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            // The sidebar's header strip, so both titles sit on one line.
            Color.clear.frame(height: Theme.Size.titleBar)

            ExplorerHeader(canCollapse: model.canCollapse) { model.collapseAll() }

            if let root = model.root {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        RootLabel(url: root)
                        ForEach(model.rows) { row in
                            ExplorerRowView(row: row, model: model)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.tight)
                    .padding(.bottom, Theme.Spacing.loose)
                }
                .scrollIndicators(.hidden)
            } else {
                Text("Select a worktree to browse its files.")
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .padding(.horizontal, Theme.Spacing.paneInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // Files are made and removed in a terminal, so coming back to the app is
        // the moment they may have changed.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await model.refresh() }
        }
    }
}

private struct ExplorerHeader: View {
    let canCollapse: Bool
    let collapseAll: () -> Void

    var body: some View {
        HStack {
            Text("Explorer")
                .font(.headline)
                .foregroundStyle(Theme.Palette.text)
            Spacer(minLength: 0)
            if canCollapse {
                Button(action: collapseAll) {
                    PhIcon(Ph.arrowsInLineVertical.regular, size: 18)
                }
                .buttonStyle(.icon)
                .help("Collapse all folders")
                // Lined up with the sidebar's add button across the window.
                .padding(.trailing, -(Theme.Size.iconButton - Theme.Size.wolfMark.width) / 2)
            }
        }
        // Holds the header's height when the button is absent.
        .frame(minHeight: Theme.Size.iconButton)
        .padding(.horizontal, Theme.Spacing.paneInset)
        .padding(.bottom, Theme.Spacing.normal)
    }
}

/// The worktree's folder name. Plain text, not a row: it has no chevron because
/// its children are always showing.
private struct RootLabel: View {
    let url: URL

    var body: some View {
        Text(url.lastPathComponent)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.Palette.secondaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
            .padding(.vertical, Theme.Spacing.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .help(url.path(percentEncoded: false))
            .contextMenu { RevealInFinder(url: url) }
    }
}

struct RevealInFinder: View {
    let url: URL

    var body: some View {
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

#if DEBUG
#Preview {
    ExplorerView(model: ExplorerModel(files: PreviewFiles()))
        .frame(width: Theme.Size.sidebarWidth, height: 420)
        .glassPaneBackground()
        .padding(Theme.Spacing.windowPadding)
        .background(Theme.Palette.window)
}

private struct PreviewFiles: FileClient {
    func read(_ path: String) async throws -> String { "" }
    func write(_ contents: String, to path: String) async throws {}
    func exists(_ path: String) async -> Bool { true }
    func children(of url: URL) async throws -> [DirectoryEntry] { [] }
}
#endif
