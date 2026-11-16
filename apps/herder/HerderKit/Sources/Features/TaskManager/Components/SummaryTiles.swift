import Core
import DesignSystem
import SwiftUI

/// CPU, memory, agent sessions and threads, for the whole of Herder's tree.
struct SummaryTiles: View {
    let model: TaskManagerModel

    var body: some View {
        let summary = model.summary
        HStack(spacing: Theme.Spacing.normal) {
            SummaryTile(
                title: "CPU",
                value: TaskFormat.share(summary?.cpuShare),
                caption: cpuCaption(summary),
                history: model.cpuHistory,
                color: Theme.Palette.accent
            )
            SummaryTile(
                title: "Memory",
                value: summary.map { TaskFormat.bytes($0.memory) } ?? TaskFormat.none,
                caption: summary.map { "of \(TaskFormat.bytes($0.physicalMemory))" } ?? "",
                history: model.memoryHistory,
                color: Theme.Palette.violet
            ) {
                if let summary { PressureBadge(pressure: summary.memoryPressure) }
            }
            SummaryTile(
                title: "Agent sessions",
                value: summary.map { String($0.sessions) } ?? TaskFormat.none,
                caption: summary.map(sessionsCaption) ?? ""
            ) {
                if let summary { SessionSplit(summary: summary) }
            }
            SummaryTile(
                title: "Threads",
                value: summary.map { String($0.threads) } ?? TaskFormat.none,
                caption: summary.map { "in \(TaskFormat.processes($0.processCount))" } ?? "",
                history: model.threadHistory,
                color: Theme.Palette.success
            )
        }
    }

    private func cpuCaption(_ summary: TaskSummary?) -> String {
        guard let summary else { return "" }
        guard let busy = summary.coresBusy else { return "of \(summary.coreCount) cores" }
        return "of \(summary.coreCount) cores \u{00B7} \(String(format: "%.1f", busy)) cores busy"
    }

    private func sessionsCaption(_ summary: TaskSummary) -> String {
        "across \(summary.workspaces) \(summary.workspaces == 1 ? "workspace" : "workspaces")"
    }
}

/// The memory-pressure level, as a coloured dot and a word.
private struct PressureBadge: View {
    let pressure: MemoryPressure

    var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Palette.text)
        }
    }

    private var label: String {
        switch pressure {
        case .low: "low"
        case .warn: "warn"
        case .critical: "critical"
        }
    }

    private var color: Color {
        switch pressure {
        case .low: Theme.Palette.success
        case .warn: Theme.Palette.warning
        case .critical: Theme.Palette.danger
        }
    }
}

/// How many of the agent sessions are working, waiting and idle.
private struct SessionSplit: View {
    let summary: TaskSummary

    var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            count(summary.working, "working", Theme.Palette.success)
            count(summary.waiting, "waiting", Theme.Palette.warning)
            count(summary.idle, "idle", Theme.Palette.tertiaryText)
        }
    }

    private func count(_ value: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(value) \(label)")
                .font(.system(size: 12))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Theme.Palette.secondaryText)
        }
    }
}
