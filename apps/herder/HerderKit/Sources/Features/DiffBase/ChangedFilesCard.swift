import Core
import DesignSystem
import SwiftUI

/// What the empty editor lists: the files that differ from the diff base,
/// under a header that holds the trigger. Not drawn for a folder that is not a
/// git repository.
public struct ChangedFilesCard: View {
    private let workspace: Workspace
    private let open: (URL) -> Void

    @State private var model: ChangedFilesModel

    private static let rowHeight: CGFloat = 28
    private static let visibleRows: CGFloat = 10

    public init(workspace: Workspace, open: @escaping (URL) -> Void) {
        self.workspace = workspace
        self.open = open
        _model = State(initialValue: ChangedFilesModel(workspace: workspace))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.fieldGroup, style: .continuous)
    }

    public var body: some View {
        if workspace.checkout != nil {
            let files = model.files ?? []
            let header = model.files.map { title(count: $0.count) } ?? ""
            VStack(spacing: 0) {
                HStack(spacing: Theme.Spacing.normal) {
                    Text(header)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    DiffBaseTrigger(workspace: workspace)
                }
                .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
                .padding(.vertical, Theme.Spacing.normal)

                if !files.isEmpty {
                    Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(files, id: \.path) { file in
                                ChangedFileRow(file: file, height: Self.rowHeight) {
                                    guard file.status != .deleted else { return }
                                    open(model.url(of: file))
                                }
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: Self.rowHeight * Self.visibleRows)
                }
            }
            .frame(maxWidth: 520)
            .background(Theme.Palette.fieldGroup, in: shape)
            .overlay { shape.strokeBorder(Theme.Palette.hairline, lineWidth: 1) }
            .task(id: workspace.id) { await model.start() }
            .onDisappear { model.stop() }
        }
    }

    private func title(count: Int) -> String {
        if count == 0 { return "No changes vs \(DiffBaseName.display(model.base.name))" }
        return count == 1 ? "1 file changed" : "\(count) files changed"
    }
}

private struct ChangedFileRow: View {
    let file: GitChangedFile
    let height: CGFloat
    let action: () -> Void

    @State private var isHovering = false

    private var name: String { (file.path as NSString).lastPathComponent }
    private var folder: String { (file.path as NSString).deletingLastPathComponent }
    private var isDeleted: Bool { file.status == .deleted }

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            Text(letter)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(colour)
                .frame(width: 14)
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.text)
                .strikethrough(isDeleted)
                .lineLimit(1)
            Text(folder)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.tertiaryText)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 0)
            LineCounts(insertions: file.insertions, deletions: file.deletions)
        }
        .opacity(isDeleted ? Theme.Opacity.ignored : 1)
        .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
        .frame(height: height)
        .background(isHovering && !isDeleted ? Theme.Palette.control : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityAddTraits(.isButton)
        .onHover { isHovering = $0 }
        .help(isDeleted ? "Deleted files can\u{2019}t be opened" : file.path)
    }

    private var letter: String {
        switch file.status {
        case .modified: "M"
        case .added: "A"
        case .deleted: "D"
        case .renamed: "R"
        }
    }

    private var colour: Color {
        switch file.status {
        case .modified: Theme.Palette.warning
        case .added: Theme.Palette.success
        case .deleted: Theme.Palette.danger
        case .renamed: Theme.Palette.accent
        }
    }
}
