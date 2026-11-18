import Core
import Foundation
import Observation

/// What the diff-base popover shows, and what picking a row does.
///
/// Made when the popover opens and dropped when it closes, so the counts are
/// worked out once per opening and nothing runs in between.
@Observable
final class DiffBasePickerModel {
    /// The three rows that do not need searching for.
    enum Preset: String, CaseIterable, Identifiable {
        case uncommitted
        case upstream
        case previousCommit

        var id: String { rawValue }

        var ref: String {
            switch self {
            case .uncommitted: GitDiffBase.head
            case .upstream: GitDiffBase.upstream
            case .previousCommit: GitDiffBase.previousCommit
            }
        }
    }

    private let workspace: Workspace

    var query = ""

    /// What `@{upstream}` stands for, once known.
    private(set) var upstreamName: String?
    private(set) var counts: [Preset: GitChangeSummary] = [:]
    private(set) var hasPreviousCommit = true
    private(set) var refs: [GitRef] = []
    private(set) var commits: [GitCommit] = []

    init(workspace: Workspace) {
        self.workspace = workspace
    }

    var base: GitDiffBase { workspace.diffBase }

    var branch: String {
        switch workspace.checkout {
        case .branch(let name)?: name
        case .detached(let sha)?: "Detached at \(sha)"
        case nil: ""
        }
    }

    var presets: [Preset] {
        Preset.allCases.filter { $0 != .previousCommit || hasPreviousCommit }
    }

    /// The ref the user picked from search, which no preset row stands for.
    var customRef: String? {
        Preset.allCases.contains { $0.ref == base.ref } ? nil : base.ref
    }

    /// What kind of thing the custom base is, for its row.
    var customKind: String {
        guard let ref = refs.first(where: { $0.name == base.ref }) else { return "Commit" }
        switch ref.kind {
        case .branch: return "Branch"
        case .remoteBranch: return "Remote branch"
        case .tag: return "Tag"
        }
    }

    var rows: [DiffBaseSearch.Row] {
        DiffBaseSearch.rows(for: query, refs: refs, commits: commits)
    }

    /// Everything the popover shows, asked for at once.
    func load() async {
        async let upstream = workspace.upstreamName()
        async let uncommitted = workspace.changeSummary(against: Preset.uncommitted.ref)
        async let toUpstream = workspace.changeSummary(against: Preset.upstream.ref)
        async let previous = workspace.changeSummary(against: Preset.previousCommit.ref)
        async let allRefs = workspace.refs()
        async let latest = workspace.recentCommits(limit: DiffBaseSearch.recentCommitCount)

        upstreamName = await upstream
        var found: [Preset: GitChangeSummary] = [:]
        if let summary = await uncommitted { found[.uncommitted] = summary }
        if let summary = await toUpstream { found[.upstream] = summary }
        let before = await previous
        if let before { found[.previousCommit] = before }
        // No merge-base for `HEAD~1` is a root commit.
        hasPreviousCommit = before != nil
        counts = found
        refs = await allRefs
        commits = await latest
    }

    func pick(_ ref: String) async {
        await workspace.setDiffBase(ref)
    }

    /// Return in the search field. `true` when it picked something.
    func submit() async -> Bool {
        let workspace = workspace
        guard let ref = await DiffBaseSearch.submission(
            for: query, rows: rows, commit: { await workspace.commit(matching: $0) }
        ) else { return false }
        await pick(ref)
        return true
    }
}
