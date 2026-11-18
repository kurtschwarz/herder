import Core
import DesignSystem
import SwiftUI

/// The popover: presets with their counts, then a search over everything else.
struct DiffBasePopover: View {
    let close: () -> Void

    /// Held here, not made by the trigger, so a redraw of the trigger while
    /// the popover is open does not hand it a fresh one with an empty search.
    @State private var model: DiffBasePickerModel
    @FocusState private var isSearching: Bool

    init(workspace: Workspace, close: @escaping () -> Void) {
        _model = State(initialValue: DiffBasePickerModel(workspace: workspace))
        self.close = close
    }

    private var searchShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.normal) {
                PhIcon(Ph.gitBranch, size: 14)
                    .foregroundStyle(Theme.Palette.secondaryText)
                Text(model.branch)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.Spacing.normal)
            .padding(.top, Theme.Spacing.normal)
            .padding(.bottom, Theme.Spacing.normal)

            heading("Show changes against")
            presetRow(.uncommitted, title: "Uncommitted", detail: "Edits since your last commit")

            heading("History")
            presetRow(
                .upstream,
                title: model.upstreamName ?? "Upstream",
                detail: "Unpushed commits plus uncommitted edits",
                isMonospaced: model.upstreamName != nil
            )
            if model.presets.contains(.previousCommit) {
                presetRow(.previousCommit, title: "HEAD~1", detail: "The last commit plus uncommitted edits", isMonospaced: true)
            }
            if let custom = model.customRef {
                OptionRow(isOn: true, action: {}) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(DiffBaseName.display(custom))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.Palette.text)
                            .lineLimit(1)
                        Text(model.customKind)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.tertiaryText)
                    }
                }
            }

            heading("Other branch, tag or commit")
            search

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.rows) { row in
                        RefRow(row: row, isOn: row.base == model.base.ref) { pick(row.base) }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 180)

            Divider().padding(.vertical, Theme.Spacing.normal)
            Text("Remembered per worktree. Drives the gutter change markers and the changed-files list.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.normal)
        }
        .padding(Theme.Spacing.normal)
        .frame(width: 320)
        .task { await model.load() }
        .onAppear { isSearching = true }
        .onExitCommand(perform: close)
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .textCase(.uppercase)
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Theme.Palette.tertiaryText)
            .padding(.horizontal, Theme.Spacing.normal)
            .padding(.top, Theme.Spacing.normal)
            .padding(.bottom, Theme.Spacing.tight)
    }

    private func presetRow(
        _ preset: DiffBasePickerModel.Preset,
        title: String,
        detail: String,
        isMonospaced: Bool = false
    ) -> some View {
        OptionRow(isOn: model.base.ref == preset.ref, action: { pick(preset.ref) }) {
            HStack(alignment: .top, spacing: Theme.Spacing.normal) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: isMonospaced ? 12 : 13, design: isMonospaced ? .monospaced : .default))
                        .foregroundStyle(Theme.Palette.text)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
                Spacer(minLength: 0)
                if let counts = model.counts[preset] {
                    LineCounts(insertions: counts.insertions, deletions: counts.deletions)
                }
            }
        }
    }

    private var search: some View {
        HStack(spacing: Theme.Spacing.normal) {
            PhIcon(Ph.magnifyingGlass, size: 14)
                .foregroundStyle(Theme.Palette.secondaryText)
            @Bindable var model = model
            TextField("Search branches, tags, commits", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearching)
                .onSubmit {
                    Task { if await model.submit() { close() } }
                }
        }
        .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
        .frame(minHeight: Theme.Size.control)
        .background(Theme.Palette.control, in: searchShape)
        .overlay {
            searchShape.strokeBorder(isSearching ? Theme.Palette.violet : Theme.Palette.hairline, lineWidth: 1)
        }
        .padding(.bottom, Theme.Spacing.normal)
    }

    private func pick(_ ref: String) {
        Task {
            await model.pick(ref)
            close()
        }
    }
}

/// A row that is a button in everything but the name: see `WorkspaceOption`.
private struct OptionRow<Content: View>: View {
    let isOn: Bool
    let action: () -> Void
    @ViewBuilder let content: Content

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            // Always takes its width, so ticked and unticked rows line up.
            PhIcon(Ph.checkBold, size: 12)
                .foregroundStyle(Theme.Palette.text)
                .opacity(isOn ? 1 : 0)
                .frame(width: 14)
            content
        }
        .padding(.horizontal, Theme.Spacing.normal)
        .padding(.vertical, Theme.Spacing.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(isHovering ? Theme.Palette.control : .clear)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .pointerStyle(.link)
        .accessibilityAddTraits(.isButton)
        .onHover { isHovering = $0 }
    }
}

/// A branch, tag or commit from search: icon, name, kind or subject, age.
private struct RefRow: View {
    let row: DiffBaseSearch.Row
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        OptionRow(isOn: isOn, action: action) {
            HStack(spacing: Theme.Spacing.normal) {
                PhIcon(icon, size: 13)
                    .foregroundStyle(Theme.Palette.secondaryText)
                Text(title)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }
        }
    }

    private var icon: Image {
        switch row {
        case .ref: Ph.gitBranch
        case .commit: Ph.gitDiff
        }
    }

    private var title: String {
        switch row {
        case .ref(let ref): ref.name
        case .commit(let commit): commit.shortSHA
        }
    }

    private var detail: String {
        switch row {
        case .ref(let ref):
            switch ref.kind {
            case .branch: "branch"
            case .remoteBranch: "remote"
            case .tag: "tag"
            }
        case .commit(let commit): commit.subject
        }
    }

    private var date: Date {
        switch row {
        case .ref(let ref): ref.date
        case .commit(let commit): commit.date
        }
    }
}
