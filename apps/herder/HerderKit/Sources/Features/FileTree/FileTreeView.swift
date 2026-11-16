import AppKit
import Core
import DesignSystem
import SwiftUI
import TestSupport

/// The file tree pane's content: a header over the tree of the selected
/// worktree.
/// What can hold keyboard focus in the file tree.
enum FileTreeFocus: Hashable {
    case tree
    case nameField
}

public struct FileTreeView: View {
    private let model: FileTreeModel

    /// Where keyboard focus is: the tree, so Return reaches it once a file has
    /// been clicked, or a name field. One value for both, so the two can never
    /// hold focus at once.
    @FocusState private var focus: FileTreeFocus?

    /// What the root is called, in place of the worktree's folder name.
    private let rootName: String?

    public init(model: FileTreeModel, rootName: String? = nil) {
        self.model = model
        self.rootName = rootName
    }

    public var body: some View {
        VStack(spacing: 0) {
            // At the pane's top, which is under the window's command bar and
            // level with the end of the sidebar's header, so the two titles
            // sit on one line.
            FileTreeHeader(canCollapse: model.canCollapse) { model.collapseAll() }

            if let root = model.root {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        RootLabel(url: root, name: rootName ?? root.lastPathComponent, model: model)
                        ForEach(model.rows) { row in
                            FileTreeRowView(row: row, model: model, focus: $focus)
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
        .alert(
            model.pendingDelete.map { "Delete \u{201C}\($0.name)\u{201D}?" } ?? "",
            isPresented: Binding(
                get: { model.pendingDelete != nil },
                set: { if !$0 { model.cancelDelete() } }
            ),
            presenting: model.pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) { Task { await model.confirmDelete(entry) } }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text(entry.isDirectory
                ? "This folder and all items inside it will be deleted immediately. You can\u{2019}t undo this action."
                : "This item will be deleted immediately. You can\u{2019}t undo this action.")
        }
        // A watcher keeps the tree honest while the window is in front. Behind,
        // changes still accumulate but are not acted on: the worst storms
        // happen while the user is in a terminal running the build causing
        // them. Coming forward is when they are worth catching up on.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.setWatching(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            model.setWatching(false)
        }
    }
}

private struct FileTreeHeader: View {
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
                    PhIcon(Ph.arrowsInLineVertical, size: 18)
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
        // Matched by the sidebar's header, so the two titles stay level.
        .padding(.top, Theme.Spacing.normal + Theme.Spacing.tight)
        .padding(.bottom, Theme.Spacing.normal)
    }
}

/// The worktree's folder name. Plain text, not a row: it has no chevron because
/// its children are always showing.
private struct RootLabel: View {
    let url: URL
    let name: String
    let model: FileTreeModel

    var body: some View {
        Text(name)
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
    let model: FileTreeModel
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
    FileTreeView(model: FileTreeModel(store: WorkspaceRegistry(
        files: PreviewFiles(),
        git: PreviewGit(),
        watcher: PreviewWatcher(),
        clock: VirtualClockClient(),
        state: InMemoryStateStore()
    )))
        .frame(width: Theme.Size.defaultSidebarWidth, height: 420)
        .glassPaneBackground()
        .padding(Theme.Spacing.windowPadding)
        .background(Theme.Palette.window)
}

private struct PreviewGit: GitClient {
    func repositoryKind(at url: URL) async throws -> GitRepositoryKind { .notARepository }
    func worktrees(at url: URL) async throws -> [GitWorktree] { [] }
    func branches(at url: URL) async throws -> [String] { [] }
    func addWorktree(in repository: URL, at path: URL, newBranch: String, from base: String) async throws {}
    func gitDirectory(of url: URL) async throws -> URL? { nil }
    func checkout(of url: URL) async throws -> GitWorktree.Checkout? { nil }
    func status(in worktree: URL) async throws -> GitWorktreeStatus { GitWorktreeStatus(root: PathKey(worktree)) }
    func changeSummary(in worktree: URL) async throws -> GitChangeSummary? { nil }
    func contents(of file: URL, atRevision revision: String, in worktree: URL) async throws -> String? { nil }
}

private struct PreviewWatcher: FileWatcherClient {
    func watch(_ roots: [URL], from position: FileWatcherPosition?) -> AsyncStream<FileChangeBatch> {
        AsyncStream { $0.finish() }
    }
}

private struct PreviewFiles: FileClient {
    func read(_ path: String) async throws -> String { "" }
    func read(_ path: String, maxBytes: Int) async throws -> String { "" }
    func write(_ contents: String, to path: String) async throws {}
    func exists(_ path: String) async -> Bool { true }
    func children(of url: URL) async throws -> [DirectoryEntry] { [] }
    func move(_ source: URL, to destination: URL) async throws {}
    func create(_ url: URL, isDirectory: Bool) async throws {}
    func delete(_ url: URL, permanently: Bool) async throws {}
}
#endif
