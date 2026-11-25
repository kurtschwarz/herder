import Core
import DesignSystem
import SwiftUI
import TestSupport

/// The editor pane's content: a breadcrumb over the open file's text. Has no
/// surface of its own: it sits straight on the window, and the file tree is the
/// only floating pane beside it. The status bar under it is the composition
/// root's, with ``EditorFileStatus`` as the editor's part of it.
///
/// Two slots, so the composition root can put another feature's views in the
/// pane without this one importing it: one at the trailing end of the
/// breadcrumb row, and one under the subtitle when no file is open.
public struct EditorView<BreadcrumbTrailing: View, EmptyState: View>: View {
    private let model: EditorModel

    @Environment(Workspace.self) private var workspace: Workspace?
    @Environment(WindowAgentSessions.self) private var sessions: WindowAgentSessions?
    @Environment(\.sendToAgentSession) private var sendToAgentSession
    @Environment(\.showAgentSession) private var showAgentSession
    @Environment(\.startAgentSession) private var startAgentSession

    /// What the first breadcrumb step is called, in place of the worktree's
    /// folder name.
    private let rootName: String?

    private let breadcrumbTrailing: BreadcrumbTrailing
    private let emptyState: EmptyState

    public init(
        model: EditorModel,
        rootName: String? = nil,
        @ViewBuilder breadcrumbTrailing: () -> BreadcrumbTrailing,
        @ViewBuilder emptyState: () -> EmptyState
    ) {
        self.model = model
        self.rootName = rootName
        self.breadcrumbTrailing = breadcrumbTrailing()
        self.emptyState = emptyState()
    }

    private var breadcrumb: [String] {
        var components = model.breadcrumb
        if let rootName, !components.isEmpty, !model.isShowingExternal { components[0] = rootName }
        return components
    }

    public var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if model.activeTab != nil {
            VStack(spacing: 0) {
                // Nothing goes higher than the pane's top, which is under the
                // window's command bar. `WindowChrome` grows the title bar so
                // the traffic lights can sit low, and AppKit backs the taller
                // bar with a full-width view that swallows clicks: a tab drawn
                // in that band is drawn but dead, which read as a tab you had
                // to click three times.
                EditorTabBar(model: model)
                Breadcrumb(components: breadcrumb, isDeleted: model.isDeleted) { breadcrumbTrailing }
                Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
                if let message = model.activeDiagnostic {
                    DiagnosticBanner(message: message)
                }
                if model.isStale {
                    StaleBanner(
                        reload: { Task { await model.reloadFromDisk() } },
                        keep: { Task { await model.keepEdits() } }
                    )
                }
                body(of: model.content)
            }
            .alert(
                model.closePrompt.map { "Do you want to save the changes to \u{201C}\($0.name)\u{201D}?" } ?? "",
                isPresented: Binding(
                    get: { model.closePrompt != nil },
                    set: { if !$0 { Task { await model.answer(.cancel) } } }
                ),
                presenting: model.closePrompt
            ) { _ in
                Button("Save") { Task { await model.answer(.save) } }
                Button("Don\u{2019}t Save", role: .destructive) { Task { await model.answer(.discard) } }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Your changes will be lost if you don\u{2019}t save them.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .alert(
                model.saveFailure.map { "Couldn\u{2019}t save \u{201C}\($0.name)\u{201D}" } ?? "",
                isPresented: Binding(
                    get: { model.saveFailure != nil },
                    set: { if !$0 { model.dismissSaveFailure() } }
                ),
                presenting: model.saveFailure
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { failure in
                Text(failure.reason)
            }
        } else {
            VStack(spacing: Theme.Spacing.normal) {
                PhIcon(Ph.file, size: 40)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                Text("No file open")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.text)
                Text("Pick a file from the explorer, or ask the agent to open one.")
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .multilineTextAlignment(.center)
                emptyState
                    .padding(.top, Theme.Spacing.normal)
            }
            .padding(Theme.Spacing.loose)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
                // As in the tab bar, empty space is where a double-click
                // starts a new file.
                .background { DoubleClickSurface { Task { await model.newUntitled() } } }
        }
    }

    @ViewBuilder
    private func body(of content: EditorModel.Content?) -> some View {
        switch content {
        case .text:
            if let buffer = model.activeBuffer, let tab = model.activeTab {
                CodeTextView(
                    buffer: buffer,
                    // An external file is in no worktree an agent works in.
                    prompt: model.isExternal(tab) ? nil : SelectionPromptContext(
                        file: tab,
                        worktree: workspace,
                        isUnsaved: model.isDirty(tab),
                        sessions: sessions,
                        send: sendToAgentSession,
                        show: showAgentSession,
                        start: startAgentSession
                    )
                )
                    .opacity(model.isDeleted ? Theme.Opacity.ignored : 1)
            }
        case .unavailable(let reason):
            Text(message(for: reason))
                .font(.callout)
                .foregroundStyle(Theme.Palette.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case nil:
            Color.clear
        }
    }

    private func message(for reason: EditorModel.Reason) -> String {
        switch reason {
        case .notText: "Can't show this file: it isn't text."
        case .tooLarge: "Can't show this file: it is larger than 1 MB."
        case .unreadable: "Can't read this file."
        }
    }
}

extension EditorView where BreadcrumbTrailing == EmptyView, EmptyState == EmptyView {
    public init(model: EditorModel, rootName: String? = nil) {
        self.init(model: model, rootName: rootName, breadcrumbTrailing: { EmptyView() }, emptyState: { EmptyView() })
    }
}

/// Shown over a buffer whose file changed on disk while it held unsaved edits.
/// Neither answer is the default: either loses something.
private struct StaleBanner: View {
    let reload: () -> Void
    let keep: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            Text("This file changed on disk.")
                .font(.callout)
                .foregroundStyle(Theme.Palette.secondaryText)
            Spacer(minLength: 0)
            Button("Reload", action: reload)
                .help("Take what is on disk and lose your changes")
            Button("Keep Mine", action: keep)
                .help("Keep your changes; saving will replace what is on disk")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, Theme.Spacing.paneInset)
        .padding(.vertical, Theme.Spacing.normal)
        .background(Theme.Palette.control)
    }
}

/// A problem with the file showing that something outside the editor found,
/// such as settings that cannot be read. Says so and asks nothing.
private struct DiagnosticBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.normal) {
            PhIcon(Ph.warningFill, size: 12)
                .foregroundStyle(Theme.Palette.warning)
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.Palette.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.paneInset)
        .padding(.vertical, Theme.Spacing.normal)
        .background(Theme.Palette.control)
    }
}

/// Where the file sits, from the worktree's folder down. Plain text: orientation,
/// not navigation. A file that has gone from disk has its name struck through.
private struct Breadcrumb<Trailing: View>: View {
    let components: [String]
    let isDeleted: Bool
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            ForEach(Array(components.enumerated()), id: \.offset) { index, name in
                if index > 0 {
                    PhIcon(Ph.caretRightBold, size: 10)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
                let isFile = index == components.count - 1
                Text(name)
                    .font(.system(size: 13, weight: isFile ? .semibold : .regular))
                    .foregroundStyle(isFile ? Theme.Palette.text : Theme.Palette.secondaryText)
                    .strikethrough(isFile && isDeleted)
                    .opacity(isFile && isDeleted ? Theme.Opacity.ignored : 1)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            // Fixed, so the breadcrumb is what truncates when the row is narrow.
            trailing
                .fixedSize()
                .layoutPriority(1)
        }
        .frame(minHeight: Theme.Size.iconButton)
        .padding(.horizontal, Theme.Spacing.paneInset)
        .padding(.top, Theme.Spacing.normal)
    }
}

#if DEBUG
#Preview {
    let files = InMemoryFileClient()
    let registry = WorkspaceRegistry(
        files: files,
        git: StubGitClient(),
        watcher: StubFileWatcherClient(),
        clock: VirtualClockClient(),
        state: InMemoryStateStore()
    )
    let model = EditorModel(store: registry, files: files, highlighter: NoSyntaxHighlighter())

    EditorView(model: model, rootName: "herder")
        .frame(width: 720, height: 420)
        .padding(Theme.Spacing.windowPadding)
        .background(Theme.Palette.window)
        // Without colour, deliberately: the real highlighter is in `Services`
        // and a feature may not import it, so what this shows is the pane —
        // breadcrumb, gutter, layout — rather than the theme. `SyntaxAttributes`
        // has the tests for the pairing.
        .task {
            let root = URL(filePath: "/preview/herder")
            let file = root.appending(path: "Workspace.swift")
            files.seed(file.path(percentEncoded: false), """
                struct Workspace {
                    let root: PathKey

                    // One checkout: a repository's worktree, or a plain folder.
                    func components(of path: PathKey) -> [String] {
                        path.components(below: root)
                    }
                }
                """)
            // A second and a third, so the bar has something to draw.
            let others = ["EditorModel.swift", "README.md"].map { root.appending(path: $0) }
            for other in others {
                files.seed(other.path(percentEncoded: false), "// \(other.lastPathComponent)\n")
            }
            files.seed(
                children: ([file] + others).map { DirectoryEntry(url: $0, isDirectory: false) },
                of: root
            )
            guard let workspace = await registry.open(WorkspaceID(root)) else { return }
            await workspace.refresh()
            for other in others.reversed() { await model.open(other) }
            await model.open(file)
        }
}
#endif
