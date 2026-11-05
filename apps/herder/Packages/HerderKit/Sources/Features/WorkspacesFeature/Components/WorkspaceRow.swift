import AppKit
import DesignSystem
import PhosphorSwift
import Storage
import SwiftUI

struct WorkspaceRow: View {
    let workspace: Repository
    let model: WorkspacesModel

    @State private var isHovering = false

    private var isAvailable: Bool { workspace.isAvailable }

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            Button {
                Task { await model.toggle(workspace) }
            } label: {
                PhIcon(Ph.caretDown.bold, size: 10)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .rotationEffect(.degrees(model.isExpanded(workspace) ? 0 : -90))
                    .animation(.easeOut(duration: 0.15), value: model.isExpanded(workspace))
                    // The hit area is the frame, not the glyph: a plain button
                    // only responds where it draws, and the chevron is a few
                    // pixels of stroke.
                    .frame(width: Theme.Size.chevron, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(isAvailable ? .link : nil)
            // An unavailable workspace has nothing to show, so there is
            // nothing to fold.
            .opacity(isAvailable ? 1 : 0)
            .disabled(!isAvailable)

            PhIcon(isAvailable ? Ph.folderSimple.duotone : Ph.warning.fill, size: 16)
                .foregroundStyle(isAvailable ? Theme.Palette.secondaryText : Theme.Palette.warning)

            if model.renaming == workspace.id {
                RenameField(name: workspace.name) { model.commitRename(workspace, to: $0) }
            } else {
                Text(workspace.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isAvailable ? Theme.Palette.text : Theme.Palette.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // On the name alone: a double-click gesture on the whole
                    // row makes every click on the chevron wait out the
                    // double-click interval before it fires.
                    .onTapGesture(count: 2) { model.renaming = workspace.id }
            }

            Spacer(minLength: 0)

            Button { model.beginNewSession(in: workspace) } label: {
                PhIcon(Ph.plus.regular, size: 12)
            }
            .buttonStyle(.icon(size: 20))
            .pointerStyle(isAvailable ? .link : nil)
            .disabled(!isAvailable)
            .help("New session")
        }
        .padding(.horizontal, Theme.Spacing.normal)
        .padding(.vertical, Theme.Spacing.tight)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(isHovering ? Theme.Palette.control : .clear)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help(isAvailable ? workspace.path : "\(workspace.path) can't be reached")
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: workspace.path)])
            }
            .disabled(!isAvailable)

            Button("Rename") { model.renaming = workspace.id }

            Divider()

            Button("Remove", role: .destructive) { model.remove(workspace) }
        }
    }
}

/// Edits a name in place. Return or clicking away keeps the edit, Escape drops
/// it; a blank name is the store's to refuse.
private struct RenameField: View {
    let commit: (String) -> Void

    @State private var text: String
    @State private var isFinished = false
    @FocusState private var isFocused: Bool

    init(name: String, commit: @escaping (String) -> Void) {
        _text = State(initialValue: name)
        self.commit = commit
    }

    var body: some View {
        TextField("Name", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.Palette.text)
            .focused($isFocused)
            .onAppear { isFocused = true }
            .onSubmit { finish(with: text) }
            .onExitCommand { finish(with: nil) }
            .onChange(of: isFocused) { _, focused in
                if !focused { finish(with: text) }
            }
    }

    /// Submitting removes the field, which drops focus, which would commit a
    /// second time: `isFinished` makes the first outcome the only one.
    private func finish(with name: String?) {
        guard !isFinished else { return }
        isFinished = true
        commit(name ?? "")
    }
}
