import Core
import DesignSystem
import SwiftUI

/// The pill that says what the editor compares with, and opens the popover to
/// change it. Not drawn for a folder that is not a git repository.
public struct DiffBaseTrigger: View {
    private let workspace: Workspace

    @State private var isOpen = false

    /// When the popover last went away. A click on the button while it is open
    /// closes it on the way down, as any click outside does, and would then
    /// open it again on the way up.
    @State private var closedAt = Date.distantPast

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
            Button {
                if isOpen {
                    isOpen = false
                } else if Date.now.timeIntervalSince(closedAt) > 0.3 {
                    isOpen = true
                }
            } label: {
                HStack(spacing: Theme.Spacing.tight + 2) {
                    PhIcon(Ph.gitDiff, size: 12)
                        .foregroundStyle(warns ? Theme.Palette.warning : Theme.Palette.secondaryText)
                    HStack(spacing: Theme.Spacing.tight) {
                        Text("Changes vs")
                            .font(.system(size: 11))
                        Text(DiffBaseName.display(base.name))
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .foregroundStyle(warns ? Theme.Palette.warning : Theme.Palette.text)
                    .lineLimit(1)
                    PhIcon(Ph.caretUpDown, size: 9)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                .padding(.horizontal, Theme.Spacing.normal)
                // Well under the breadcrumb row, which has no padding below
                // it: at the row's own height the pill touches the hairline.
                .frame(minHeight: 20)
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
            .onHover { if $0 { Task { await DiffBasePickerModel.prefetch(for: workspace) } } }
            .onChange(of: isOpen) { _, open in
                if !open { closedAt = .now }
            }
            .background {
                UnanimatedPopover(isPresented: $isOpen) {
                    DiffBasePopover(workspace: workspace) { isOpen = false }
                }
            }
        }
    }
}
