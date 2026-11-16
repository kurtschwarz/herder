import Foundation

/// Turns a sample into the Task Manager's rows: which processes belong to
/// which tab, and what is left over.
///
/// ```
/// Agent Sessions         one row per open agent tab, over its process tree
/// Herder                 Herder's own process,
///   Terminals            then each shell tab over its tree,
///   Other                then children no tab claims (hidden when empty)
/// ```
///
/// Pure: the sample, the rates and the tabs go in, and nothing is read from
/// the system.
public enum TaskTree {
    public static let appName = "Herder"

    public static func build(sample: ProcessSample, cpu: [ProcessKey: Double], owners: [ProcessOwner]) -> [TaskRow] {
        var builder = Builder(sample: sample, cpu: cpu)
        let sessions = owners.filter { $0.kind == .agentSession }.map { builder.tabRow($0) }
        let terminals = owners.filter { $0.kind == .terminal }.map { builder.tabRow($0) }

        var herder: [TaskRow] = []
        if let root = builder.byPID[sample.root] { herder.append(builder.appRow(root)) }
        herder.append(.group(.terminals, name: "Terminals", children: terminals))

        // What no tab claimed, still under Herder: a `git` that a status
        // refresh started, or anything else the app launched on its own.
        let claimed = Set(owners.compactMap(\.pid))
        let others = (builder.childrenOf[sample.root] ?? [])
            .filter { !claimed.contains($0.pid) }
            .map { builder.processRow($0) }
        if !others.isEmpty { herder.append(.group(.other, name: "Other", children: others)) }

        return [
            .group(.agentSessions, name: "Agent Sessions", children: sessions),
            .group(.herder, name: appName, children: herder),
        ]
    }

    private struct Builder {
        let cpu: [ProcessKey: Double]
        let byPID: [Int32: SampledProcess]
        let childrenOf: [Int32: [SampledProcess]]

        /// Every process put in a row so far, so that none is in two, which a
        /// pid that loops back on itself would otherwise do.
        var placed: Set<Int32> = []

        init(sample: ProcessSample, cpu: [ProcessKey: Double]) {
            self.cpu = cpu
            byPID = Dictionary(sample.processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
            childrenOf = Dictionary(
                grouping: sample.processes.filter { $0.pid != $0.parent },
                by: \.parent
            ).mapValues { $0.sorted { $0.pid < $1.pid } }
        }

        mutating func processRow(_ process: SampledProcess) -> TaskRow {
            placed.insert(process.pid)
            var children: [TaskRow] = []
            for child in childrenOf[process.pid] ?? [] where !placed.contains(child.pid) {
                children.append(processRow(child))
            }
            var row = TaskRow(
                id: .process(process.key),
                kind: .process,
                name: process.name,
                subtitle: "pid \(process.pid)",
                help: process.commandLine,
                status: process.isRunning ? .running : .sleeping,
                cpu: cpu[process.key],
                memory: process.footprint,
                threads: process.threads,
                processCount: 1,
                startedAt: process.startedAt,
                pid: process.pid,
                searchTerms: [String(process.pid)],
                children: children
            )
            row.addTotals(of: children)
            return row
        }

        /// Herder's own process: just it, because everything under it is
        /// shown under the row that owns it.
        mutating func appRow(_ process: SampledProcess) -> TaskRow {
            placed.insert(process.pid)
            return TaskRow(
                id: .process(process.key),
                kind: .herder,
                name: appName,
                subtitle: "App \u{00B7} pid \(process.pid)",
                help: process.commandLine,
                status: process.isRunning ? .running : .sleeping,
                cpu: cpu[process.key],
                memory: process.footprint,
                threads: process.threads,
                processCount: 1,
                startedAt: process.startedAt,
                pid: process.pid,
                searchTerms: [String(process.pid)]
            )
        }

        mutating func tabRow(_ owner: ProcessOwner) -> TaskRow {
            let hasExited: Bool = if case .exited = owner.state { true } else { false }
            let process = hasExited ? nil : owner.pid.flatMap { byPID[$0] }
            let children = process.map { [processRow($0)] } ?? []

            let worktree = owner.worktree.root.name
            var row = TaskRow(
                id: .tab(owner.id),
                kind: owner.kind == .agentSession ? .session : .terminal,
                name: owner.title,
                subtitle: owner.branch.map { "\(worktree) \u{00B7} \($0)" } ?? worktree,
                help: process?.commandLine,
                status: status(of: owner, process: children.first),
                startedAt: process?.startedAt,
                pid: process?.pid ?? owner.pid,
                searchTerms: [worktree, owner.branch, owner.pid.map(String.init)].compactMap { $0 },
                children: children
            )
            row.addTotals(of: children)
            // Nothing running under it, and so nothing used: zeros, not a
            // dash, which would say it has not been measured yet.
            if children.isEmpty { row.cpu = 0 }
            return row
        }

        private func status(of owner: ProcessOwner, process: TaskRow?) -> TaskRow.Status {
            guard owner.kind == .agentSession else { return process?.status ?? .none }
            switch owner.state {
            case .working: return .working
            case .needsInput: return .needsYou
            case .starting: return .starting
            case .failed: return .failed
            case .exited: return .done
            case .paused: return .paused
            case .idle, nil: return .idle
            }
        }
    }
}
