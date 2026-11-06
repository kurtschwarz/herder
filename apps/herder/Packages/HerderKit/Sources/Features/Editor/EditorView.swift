import Core
import DesignSystem
import PhosphorSwift
import SwiftUI
import TestSupport

/// The editor pane's content: a breadcrumb over the open file's text. Has no
/// surface of its own: it sits straight on the window, and the file tree is the
/// only floating pane beside it.
public struct EditorView: View {
    private let model: EditorModel

    /// What the first breadcrumb step is called, in place of the worktree's
    /// folder name.
    private let rootName: String?

    public init(model: EditorModel, rootName: String? = nil) {
        self.model = model
        self.rootName = rootName
    }

    private var breadcrumb: [String] {
        var components = model.breadcrumb
        if let rootName, !components.isEmpty { components[0] = rootName }
        return components
    }

    public var body: some View {
        if model.file != nil {
            VStack(spacing: 0) {
                // The window's header strip, kept clear for the same reason
                // the file tree keeps it clear — but here it is load-bearing
                // rather than cosmetic. `WindowChrome` grows the title bar so
                // the traffic lights can sit low, and AppKit backs the taller
                // bar with a full-width view that swallows clicks. A tab drawn
                // in that band is drawn but dead, which read as a tab you had
                // to click three times.
                Color.clear.frame(height: Theme.Size.titleBar)

                EditorTabBar(model: model)
                Breadcrumb(components: breadcrumb, isDeleted: model.isDeleted)
                Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
                body(of: model.content)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            Text("Select a file to read it.")
                .font(.callout)
                .foregroundStyle(Theme.Palette.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func body(of content: EditorModel.Content?) -> some View {
        switch content {
        case .text(let source):
            // There is content only because a tab is showing, so the `if let`
            // never fails; it is how the tab reaches the scroll position it
            // was left at.
            if let tab = model.activeTab {
                CodeTextView(
                    source: source,
                    session: model.session,
                    restoring: model.offset(of: tab),
                    onLeave: { model.rememberOffset($0, of: tab) }
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

/// Where the file sits, from the worktree's folder down. Plain text: orientation,
/// not navigation. A file that has gone from disk has its name struck through.
private struct Breadcrumb: View {
    let components: [String]
    let isDeleted: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            ForEach(Array(components.enumerated()), id: \.offset) { index, name in
                if index > 0 {
                    PhIcon(Ph.caretRight.bold, size: 10)
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
        }
        .frame(minHeight: Theme.Size.iconButton)
        .padding(.horizontal, Theme.Spacing.paneInset)
        .padding(.vertical, Theme.Spacing.normal)
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
