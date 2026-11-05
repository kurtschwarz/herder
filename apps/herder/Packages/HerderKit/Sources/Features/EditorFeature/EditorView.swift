import DesignSystem
import PhosphorSwift
import SwiftUI

/// The editor pane's content: a breadcrumb over the open file's text. Has no
/// surface of its own: it sits straight on the window, and the explorer is the
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
            CodeTextView(source: source, session: model.session)
                .opacity(model.isDeleted ? Theme.Opacity.ignored : 1)
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
