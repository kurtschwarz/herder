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
    private let cache: DiffBaseCache

    var query = ""

    /// What `@{upstream}` stands for, once known.
    private(set) var upstreamName: String?
    private(set) var counts: [Preset: GitChangeSummary] = [:]
    private(set) var hasPreviousCommit = true
    private(set) var refs: [GitRef] = []
    private(set) var commits: [GitCommit] = []

    init(workspace: Workspace) {
        self.workspace = workspace
        let cache = workspace.uiState(DiffBaseCache.self)
        self.cache = cache
        upstreamName = cache.upstreamName
        counts = cache.counts
        hasPreviousCommit = cache.hasPreviousCommit
        refs = cache.refs
        commits = cache.commits
    }

    /// Fills the cache ahead of the popover opening, unless it was filled
    /// moments ago. Asked for when the pointer reaches the trigger, which is
    /// the one thing that says a popover is about to be wanted.
    static func prefetch(for workspace: Workspace) async {
        let cache = workspace.uiState(DiffBaseCache.self)
        if let loadedAt = cache.loadedAt, Date.now.timeIntervalSince(loadedAt) < 5 { return }
        await DiffBasePickerModel(workspace: workspace).load()
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
        let isPreset = Preset.allCases.contains { $0.ref == base.ref } || base.ref == upstreamName
        return isPreset ? nil : base.ref
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

    /// How many rows are drawn. A repository with thousands of tags would
    /// otherwise build every row each time the popover opens; typing narrows
    /// the list to what is wanted.
    static let visibleRowLimit = 40

    /// The rows to draw, and whether more matched than are drawn.
    var visibleRows: (rows: [DiffBaseSearch.Row], isTruncated: Bool) {
        let all = rows
        return (Array(all.prefix(Self.visibleRowLimit)), all.count > Self.visibleRowLimit)
    }

    /// Everything the popover shows, asked for at once.
    func load() async {
        async let upstream = workspace.upstreamName()
        async let uncommitted = workspace.changeSummary(against: Preset.uncommitted.ref)
        async let toUpstream = workspace.changeSummary(against: Preset.upstream.ref)
        async let previous = workspace.changeSummary(against: Preset.previousCommit.ref)
        async let allRefs = workspace.refs()
        async let latest = workspace.recentCommits(limit: DiffBaseSearch.recentCommitCount)

        // Everything is waited for before anything is set, so the popover
        // redraws once with the lot instead of once per answer.
        let (name, now, ahead, before) = await (upstream, uncommitted, toUpstream, previous)
        let (allRefsFound, latestFound) = await (allRefs, latest)

        var found: [Preset: GitChangeSummary] = [:]
        if let now { found[.uncommitted] = now }
        if let ahead { found[.upstream] = ahead }
        if let before { found[.previousCommit] = before }
        // Only what differs is set, so a reload that found nothing new does
        // not redraw.
        if upstreamName != name { upstreamName = name }
        // No merge-base for `HEAD~1` is a root commit.
        if hasPreviousCommit != (before != nil) { hasPreviousCommit = before != nil }
        if counts != found { counts = found }
        if refs != allRefsFound { refs = allRefsFound }
        if commits != latestFound { commits = latestFound }

        cache.upstreamName = upstreamName
        cache.counts = counts
        cache.hasPreviousCommit = hasPreviousCommit
        cache.refs = refs
        cache.commits = commits
        cache.loadedAt = .now
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
