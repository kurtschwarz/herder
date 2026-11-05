import AppKit
import Clients
import DesignSystem
import PhosphorSwift
import SwiftUI

/// The explorer pane's content: a header over the file tree of the selected
/// worktree.
/// What can hold keyboard focus in the explorer.
enum ExplorerFocus: Hashable {
    case tree
    case nameField
}

public struct ExplorerView: View {
    private let model: ExplorerModel

    /// Where keyboard focus is: the tree, so Return reaches it once a file has
    /// been clicked, or a name field. One value for both, so the two can never
    /// hold focus at once.
    @FocusState private var focus: ExplorerFocus?

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
                        RootLabel(url: root, model: model)
                        ForEach(model.rows) { row in
                            ExplorerRowView(row: row, model: model, focus: $focus)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.tight)
                    .padding(.bottom, Theme.Spacing.loose)
                }
                .scrollIndicators(.hidden)
                // Empty space below the rows. A row's own menu wins over this one.
                .contextMenu { NewItemMenu(model: model, folder: root) }
                .focusable()
                .focused($focus, equals: .tree)
                .focusEffectDisabled()
                .onKeyPress(.return) {
                    // Return in a name field also reaches here, and the file
                    // just created is selected: without this it would start
                    // renaming that file and drop the folder being named.
                    guard let selected = model.selected, !model.isEditingName else { return .ignored }
                    model.beginRenaming(selected)
                    return .handled
                }
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
    let model: ExplorerModel

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
            .contextMenu {
                NewItemMenu(model: model, folder: url)
                Divider()
                RevealInFinder(url: url)
            }
    }
}

/// New File and New Folder, creating inside `folder`.
struct NewItemMenu: View {
    let model: ExplorerModel
    let folder: URL

    var body: some View {
        Button("New File") { Task { await model.beginCreating(in: folder, isDirectory: false) } }
        Button("New Folder") { Task { await model.beginCreating(in: folder, isDirectory: true) } }
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
    func move(_ source: URL, to destination: URL) async throws {}
    func create(_ url: URL, isDirectory: Bool) async throws {}
}
#endif
