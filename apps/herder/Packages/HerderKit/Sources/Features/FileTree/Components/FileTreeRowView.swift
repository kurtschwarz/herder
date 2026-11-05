import AppKit
import Core
import DesignSystem
import PhosphorSwift
import SwiftUI

/// One line of the tree: a folder that opens and closes, a file that selects, or
/// the note standing in for a folder that could not be read.
struct FileTreeRowView: View {
    let row: FileTreeRow
    let model: FileTreeModel
    let focus: FocusState<FileTreeFocus?>.Binding

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
            EntryLine(
                entry: entry,
                parent: row.parent,
                isIgnored: row.isIgnored,
                mark: row.mark,
                model: model,
                focus: focus,
                isHovering: $isHovering
            )
        case .creating(let isDirectory):
            CreatingLine(isDirectory: isDirectory, model: model, focus: focus)
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
    let parent: URL
    let isIgnored: Bool
    let mark: GitMark?
    let model: FileTreeModel
    let focus: FocusState<FileTreeFocus?>.Binding
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
                RenameField(name: entry.name, isFolder: entry.isDirectory, focus: focus) { name in
                    focus.wrappedValue = .tree
                    Task { await model.commitRename(entry, to: name) }
                } cancel: {
                    focus.wrappedValue = .tree
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

            if let mark {
                Text(markLetter(mark))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? Theme.Palette.onViolet : markColor(mark))
                    .help(markHelp(mark))
            }
        }
        .opacity(isIgnored ? Theme.Opacity.ignored : 1)
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
            // A name field being edited is an AppKit field editor, which keeps
            // first responder through a click on a view that cannot take it.
            NSApp.keyWindow?.makeFirstResponder(nil)
            focus.wrappedValue = .tree
            if entry.isDirectory {
                Task { await model.toggle(entry.url) }
            } else {
                model.select(entry.url)
            }
        }
        .help(entry.url.path(percentEncoded: false))
        .contextMenu {
            // A folder is made into; a file's neighbours are made beside it.
            NewItemMenu(model: model, folder: entry.isDirectory ? entry.url : parent)
            Divider()
            Button("Rename") { model.beginRenaming(entry.url) }
            RevealInFinder(url: entry.url)
        }
    }

    private var fill: Color {
        if isSelected { return Theme.Palette.violet }
        return isHovering ? Theme.Palette.control : .clear
    }

    /// Git's own shorthand, which anybody who reads `git status` already knows.
    private func markLetter(_ mark: GitMark) -> String {
        switch mark {
        case .untracked: "?"
        case .modified: "M"
        case .unmerged: "!"
        }
    }

    private func markColor(_ mark: GitMark) -> Color {
        switch mark {
        case .untracked: Theme.Palette.accent
        case .modified: Theme.Palette.warning
        case .unmerged: Theme.Palette.danger
        }
    }

    /// A closed folder's mark is about what is inside it, not about the folder.
    private func markHelp(_ mark: GitMark) -> String {
        let inside = entry.isDirectory
        switch mark {
        case .untracked: return inside ? "Untracked files inside" : "Untracked"
        case .modified: return inside ? "Changes inside" : "Changed"
        case .unmerged: return inside ? "Conflicts inside" : "Conflicted"
        }
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

/// The name field of a file or folder about to be made, drawn where it will
/// appear.
private struct CreatingLine: View {
    let isDirectory: Bool
    let model: FileTreeModel
    let focus: FocusState<FileTreeFocus?>.Binding

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            Color.clear.frame(width: Theme.Size.treeIndent - Theme.Spacing.tight, height: 1)

            PhIcon(isDirectory ? Ph.folderSimple.duotone : Ph.file.regular, size: 16)
                .foregroundStyle(isDirectory ? Theme.Palette.violet : Theme.Palette.tertiaryText)

            RenameField(name: "", isFolder: isDirectory, focus: focus) { name in
                focus.wrappedValue = .tree
                Task { await model.commitCreating(named: name) }
            } cancel: {
                focus.wrappedValue = .tree
                model.cancelCreating()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.normal)
        .padding(.vertical, Theme.Spacing.tight + 2)
    }
}

/// Edits a name in place. Return or clicking away keeps the edit, Escape drops
/// it. Opens with the name selected up to its extension, so typing replaces
/// `Notes` in `Notes.md` and leaves `.md` alone.
private struct RenameField: View {
    let focus: FocusState<FileTreeFocus?>.Binding
    let commit: (String) -> Void
    let cancel: () -> Void

    @State private var text: String
    @State private var selection: TextSelection?
    @State private var isFinished = false
    @State private var hasHadFocus = false

    private let stemEnd: String.Index

    init(
        name: String,
        isFolder: Bool,
        focus: FocusState<FileTreeFocus?>.Binding,
        commit: @escaping (String) -> Void,
        cancel: @escaping () -> Void
    ) {
        _text = State(initialValue: name)
        self.focus = focus
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
            .focused(focus, equals: .nameField)
            .onAppear {
                // Not at once: a context menu hands focus back to what had it
                // as it closes, which would take it from a field already
                // focused.
                Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    focus.wrappedValue = .nameField
                }
                // After the field takes focus, which selects everything.
                Task { try? await Task.sleep(for: .milliseconds(150)); selection = TextSelection(range: text.startIndex..<stemEnd) }
            }
            .onSubmit { finish(commit: true) }
            .onExitCommand { finish(commit: false) }
            .onChange(of: focus.wrappedValue) { _, now in
                // Focus moving about before the field has it is not the user
                // clicking away.
                if now == .nameField {
                    hasHadFocus = true
                } else if hasHadFocus {
                    finish(commit: true)
                }
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
