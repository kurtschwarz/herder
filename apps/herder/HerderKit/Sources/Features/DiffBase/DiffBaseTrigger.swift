import Core
import DesignSystem
import SwiftUI

/// The pill that says what the editor compares with, and opens the popover to
/// change it. Not drawn for a folder that is not a git repository.
public struct DiffBaseTrigger: View {
    private let workspace: Workspace

    @State private var isOpen = false

    public init(workspace: Workspace) {
        self.workspace = workspace
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
    }

    public var body: some View {
        if workspace.checkout != nil {
            let base = workspace.diffBase
            let warns = !base.isResolved
            Button { isOpen.toggle() } label: {
                HStack(spacing: Theme.Spacing.normal) {
                    PhIcon(Ph.gitDiff, size: 14)
                        .foregroundStyle(warns ? Theme.Palette.warning : Theme.Palette.secondaryText)
                    HStack(spacing: Theme.Spacing.tight) {
                        Text("Changes vs")
                            .font(.system(size: 12))
                        Text(DiffBaseName.display(base.name))
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .foregroundStyle(warns ? Theme.Palette.warning : Theme.Palette.text)
                    .lineLimit(1)
                    PhIcon(Ph.caretUpDown, size: 10)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
                .frame(minHeight: Theme.Size.iconButton)
                .background(warns ? Theme.Palette.warning.opacity(0.12) : Theme.Palette.control, in: shape)
                .overlay {
                    shape.strokeBorder(
                        isOpen ? Theme.Palette.violet : (warns ? Theme.Palette.warning : Theme.Palette.hairline),
                        lineWidth: 1
                    )
                }
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help(warns ? DiffBaseName.warning(for: base) : "Choose what the editor compares with")
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                DiffBasePopover(model: DiffBasePickerModel(workspace: workspace)) { isOpen = false }
            }
        }
    }
}
