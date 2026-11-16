import Core
import DesignSystem
import SwiftUI

/// The column titles. Clicking one sorts the rows among their siblings, and
/// clicking it again turns the sort round.
struct TaskTableHeader: View {
    let model: TaskManagerModel

    var body: some View {
        HStack(spacing: 0) {
            cell("Name", .name, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            cell("Status", .status, alignment: .leading).frame(width: TaskColumns.status, alignment: .leading)
            cell("CPU", .cpu, alignment: .trailing).frame(width: TaskColumns.cpu, alignment: .trailing)
            cell("Memory", .memory, alignment: .trailing).frame(width: TaskColumns.memory, alignment: .trailing)
            cell("Threads", .threads, alignment: .trailing).frame(width: TaskColumns.threads, alignment: .trailing)
            cell("Procs", .processes, alignment: .trailing).frame(width: TaskColumns.processes, alignment: .trailing)
            cell("Uptime", .uptime, alignment: .trailing).frame(width: TaskColumns.uptime, alignment: .trailing)
        }
        .padding(.horizontal, TaskColumns.inset)
        .frame(height: 30)
    }

    private func cell(_ title: String, _ column: TaskSort.Column, alignment: Alignment) -> some View {
        let isSorted = model.order.column == column
        return Button {
            model.sort(by: column)
        } label: {
            HStack(spacing: 3) {
                if alignment == .trailing, isSorted { arrow }
                Text(title)
                if alignment == .leading, isSorted { arrow }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isSorted ? Theme.Palette.text : Theme.Palette.tertiaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var arrow: some View {
        PhIcon(Ph.caretDownBold, size: 8)
            .rotationEffect(model.order.ascending ? .degrees(180) : .zero)
    }
}
