import Core
import DesignSystem
import SwiftUI

/// One line of the table: its place in the tree, its name, and its numbers.
struct TaskTableRow: View {
    let line: TaskLine
    let now: Date?
    let isSelected: Bool
    let toggle: () -> Void
    let select: () -> Void

    private var row: TaskRow { line.row }

    var body: some View {
        HStack(spacing: 0) {
            name.frame(maxWidth: .infinity, alignment: .leading)
            status.frame(width: TaskColumns.status, alignment: .leading)
            CPUCell(percent: row.cpu).frame(width: TaskColumns.cpu, alignment: .trailing)
            number(TaskFormat.bytes(row.memory)).frame(width: TaskColumns.memory, alignment: .trailing)
            number("\(row.threads)").frame(width: TaskColumns.threads, alignment: .trailing)
            number("\(row.processCount)").frame(width: TaskColumns.processes, alignment: .trailing)
            number(row.isGroup ? "" : TaskFormat.uptime(from: row.startedAt, to: now))
                .frame(width: TaskColumns.uptime, alignment: .trailing)
        }
        .padding(.horizontal, TaskColumns.inset)
        .frame(height: row.isGroup ? 30 : 38)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.Palette.control)
                    .padding(.horizontal, Theme.Spacing.tight)
            } else if row.isGroup {
                Theme.Palette.currentLine
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .help(row.help ?? "")
    }

    private var name: some View {
        HStack(spacing: Theme.Spacing.normal) {
            Color.clear.frame(width: CGFloat(line.depth) * Theme.Size.treeIndent, height: 1)

            Button(action: toggle) {
                PhIcon(line.isExpanded ? Ph.caretDownBold : Ph.caretRightBold, size: 9)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .frame(width: Theme.Size.chevron, height: Theme.Size.chevron)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(line.hasChildren ? 1 : 0)
            .disabled(!line.hasChildren)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.system(size: 13, weight: row.isGroup || row.kind == .session ? .semibold : .regular))
                    .foregroundStyle(row.isGroup ? Theme.Palette.secondaryText : Theme.Palette.text)
                    .lineLimit(1)
                if let subtitle = row.subtitle, !row.isGroup {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let label = Self.label(row.status) {
            HStack(spacing: 6) {
                Circle().fill(Self.color(row.status)).frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
        }
    }

    private func number(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(row.isGroup ? Theme.Palette.secondaryText : Theme.Palette.text)
            .lineLimit(1)
    }

    static func label(_ status: TaskRow.Status) -> String? {
        switch status {
        case .working: "Working"
        case .needsYou: "Needs you"
        case .idle: "Idle"
        case .starting: "Starting"
        case .failed: "Failed"
        case .done: "Done"
        case .running: "Running"
        case .sleeping: "Sleeping"
        case .none: nil
        }
    }

    static func color(_ status: TaskRow.Status) -> Color {
        switch status {
        case .working, .running: Theme.Palette.success
        case .needsYou: Theme.Palette.warning
        case .failed: Theme.Palette.danger
        case .idle, .starting, .done, .sleeping, .none: Theme.Palette.tertiaryText
        }
    }
}

/// A rate and a small bar under it, filled by how much of a core it is.
private struct CPUCell: View {
    let percent: Double?

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            Text(TaskFormat.cpu(percent))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.text)
            Capsule()
                .fill(Theme.Palette.control)
                .frame(width: 44, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Palette.accent)
                        .frame(width: 44 * min(max((percent ?? 0) / 100, 0), 1), height: 4)
                }
        }
    }
}
