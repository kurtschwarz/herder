import Clients
import DesignSystem
import PhosphorSwift
import SwiftUI

/// One line of the tree: a folder that opens and closes, a file that selects, or
/// the note standing in for a folder that could not be read.
struct ExplorerRowView: View {
    let row: ExplorerRow
    let model: ExplorerModel
    let focusTree: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<row.depth, id: \.self) { _ in
                Rectangle()
                    .fill(Theme.Palette.hairline)
                    .frame(width: 1)
                    .frame(width: Theme.Size.treeIndent)
                    .opacity(isHovering ? 0 : 1)
            }
            content
        }
        .padding(.leading, Theme.Spacing.normal + Theme.Spacing.tight)
    }

    @ViewBuilder
    private var content: some View {
        switch row.kind {
        case .entry(let entry):
            EntryLine(entry: entry, model: model, focusTree: focusTree, isHovering: $isHovering)
        case .unreadable:
            Text("Can't read")
                .font(.callout)
                .foregroundStyle(Theme.Palette.tertiaryText)
                .padding(.vertical, Theme.Spacing.tight)
                .padding(.leading, Theme.Size.treeIndent + Theme.Spacing.normal)
        }
    }
}

private struct EntryLine: View {
    let entry: DirectoryEntry
    let model: ExplorerModel
    let focusTree: () -> Void
    @Binding var isHovering: Bool

    private var isSelected: Bool { !entry.isDirectory && model.selected == entry.url }

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            if entry.isDirectory {
                PhIcon(Ph.caretDown.bold, size: 10)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .rotationEffect(.degrees(model.isExpanded(entry.url) ? 0 : -90))
                    .animation(.easeOut(duration: 0.15), value: model.isExpanded(entry.url))
                    .frame(width: Theme.Size.treeIndent - Theme.Spacing.tight)
            } else {
                Color.clear.frame(width: Theme.Size.treeIndent - Theme.Spacing.tight, height: 1)
            }

            PhIcon(entry.isDirectory ? Ph.folderSimple.duotone : Ph.file.regular, size: 16)
                .foregroundStyle(iconColor)

            if model.renaming == entry.url {
                RenameField(name: entry.name, isFolder: entry.isDirectory) { name in
                    focusTree()
                    Task { await model.commitRename(entry, to: name) }
                } cancel: {
                    focusTree()
                    model.cancelRenaming()
                }
            } else {
                Text(entry.name)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Theme.Palette.onViolet : Theme.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.normal)
        .padding(.vertical, Theme.Spacing.tight + 2)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(fill)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            guard model.renaming != entry.url else { return }
            focusTree()
            if entry.isDirectory {
                Task { await model.toggle(entry.url) }
            } else {
                model.select(entry.url)
            }
        }
        .help(entry.url.path(percentEncoded: false))
        .contextMenu {
            Button("Rename") { model.beginRenaming(entry.url) }
            RevealInFinder(url: entry.url)
        }
    }

    private var fill: Color {
        if isSelected { return Theme.Palette.violet }
        return isHovering ? Theme.Palette.control : .clear
    }

    private var iconColor: Color {
        if entry.isDirectory { return Theme.Palette.violet }
        if isSelected { return Theme.Palette.onViolet }
        switch entry.url.pathExtension.lowercased() {
        case "swift": return Theme.Palette.warning
        case "md", "json", "yml", "yaml", "toml": return Theme.Palette.accent
        case "png", "jpg", "jpeg", "gif", "svg", "pdf": return Theme.Palette.violet
        default: return Theme.Palette.tertiaryText
        }
    }
}

/// Edits a name in place. Return or clicking away keeps the edit, Escape drops
/// it. Opens with the name selected up to its extension, so typing replaces
/// `Notes` in `Notes.md` and leaves `.md` alone.
private struct RenameField: View {
    let commit: (String) -> Void
    let cancel: () -> Void

    @State private var text: String
    @State private var selection: TextSelection?
    @State private var isFinished = false
    @FocusState private var isFocused: Bool

    private let stemEnd: String.Index

    init(name: String, isFolder: Bool, commit: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        _text = State(initialValue: name)
        self.commit = commit
        self.cancel = cancel
        let dot = name.lastIndex(of: ".")
        // A leading dot is part of the name, not an extension.
        stemEnd = if !isFolder, let dot, dot != name.startIndex { dot } else { name.endIndex }
    }

    var body: some View {
        TextField("Name", text: $text, selection: $selection)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.Palette.text)
            .focused($isFocused)
            .onAppear {
                isFocused = true
                // After the field takes focus, which selects everything.
                Task { selection = TextSelection(range: text.startIndex..<stemEnd) }
            }
            .onSubmit { finish(commit: true) }
            .onExitCommand { finish(commit: false) }
            .onChange(of: isFocused) { _, focused in
                if !focused { finish(commit: true) }
            }
    }

    /// Submitting removes the field, which drops focus, which would commit a
    /// second time: `isFinished` makes the first outcome the only one.
    private func finish(commit shouldCommit: Bool) {
        guard !isFinished else { return }
        isFinished = true
        if shouldCommit { commit(text) } else { cancel() }
    }
}
