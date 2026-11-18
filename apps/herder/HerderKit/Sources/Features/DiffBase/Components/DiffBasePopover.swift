import Core
import DesignSystem
import SwiftUI

/// The popover: a strip of the usual bases, what the picked one means, and a
/// search over everything else with the most recent refs as chips.
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

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.fieldGroup, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
            HStack(spacing: Theme.Spacing.normal) {
                Text("Compare against")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.text)
                Spacer(minLength: Theme.Spacing.normal)
                Text(model.branch)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            segments

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.normal) {
                Text(model.selectedSegment?.detail ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let counts = model.selectedCounts {
                    LineCounts(insertions: counts.insertions, deletions: counts.deletions)
                }
            }
            // Two lines tall whether or not the text needs them, so choosing
            // another segment never moves what is under it.
            .frame(minHeight: 34, alignment: .top)

            Divider()

            search
            chips
        }
        .padding(Theme.Spacing.normal + Theme.Spacing.tight)
        // The arrow takes some of the top edge, so the header needs more
        // room above it than the sides have.
        .padding(.top, Theme.Spacing.tight)
        .frame(width: 340)
        .task {
            // After the opening animation, which a relayout would drop frames
            // from. What was cached is already showing.
            try? await Task.sleep(for: .milliseconds(300))
            await model.load()
        }
        .onAppear { isSearching = true }
        .onExitCommand(perform: close)
    }

    private var segments: some View {
        HStack(spacing: 2) {
            ForEach(model.segments) { segment in
                let isOn = model.selectedSegment?.ref == segment.ref
                Text(segment.label)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(isOn ? Theme.Palette.text : Theme.Palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, Theme.Spacing.normal)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background {
                        if isOn {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(Theme.Palette.controlPressed)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { pick(segment.ref) }
                    .pointerStyle(.link)
                    .accessibilityAddTraits(.isButton)
            }
        }
        .padding(3)
        .background(Theme.Palette.field, in: fieldShape)
        .overlay { fieldShape.strokeBorder(Theme.Palette.hairline, lineWidth: 1) }
    }

    private var search: some View {
        HStack(spacing: Theme.Spacing.normal) {
            PhIcon(Ph.magnifyingGlass, size: 14)
                .foregroundStyle(Theme.Palette.secondaryText)
            @Bindable var model = model
            TextField("Other branch, tag or SHA", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearching)
                .onSubmit {
                    Task { if await model.submit() { close() } }
                }
        }
        .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
        .frame(minHeight: Theme.Size.control + 4)
        .background(Theme.Palette.field, in: fieldShape)
        .overlay {
            fieldShape.strokeBorder(isSearching ? Theme.Palette.violet : Theme.Palette.hairline, lineWidth: 1)
        }
    }

    private var chips: some View {
        let visible = model.visibleRows
        return ScrollView {
            FlowLayout(spacing: Theme.Spacing.normal) {
                ForEach(visible.rows) { row in
                    RefChip(row: row, isOn: row.base == model.base.ref) { pick(row.base) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Fixed, so the popover is the same size when it opens as when the
        // answers arrive: a size that changes under the opening animation is
        // what makes it stutter.
        .frame(height: 104)
    }

    /// Stays open, so the choice can be seen taking effect and changed again.
    /// Return in the search field is what closes it.
    private func pick(_ ref: String) {
        Task {
            await model.pick(ref)
            // A base picked from search has no counts until it is asked for.
            await model.load()
        }
    }
}

/// A branch, tag or commit from search, as a pill.
private struct RefChip: View {
    let row: DiffBaseSearch.Row
    let isOn: Bool
    let action: () -> Void

    @State private var isHovering = false

    /// The popover's width less its padding and the scroll bar.
    private static let maxWidth: CGFloat = 300

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            PhIcon(icon, size: 13)
                .foregroundStyle(Theme.Palette.secondaryText)
            Text(title)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.Palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
        // A chip is as wide as its name, and a name can be longer than the
        // popover: capped, the name is cut in the middle instead of widening
        // everything above it.
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
        .frame(height: 28)
        .background(isHovering ? Theme.Palette.controlPressed : Theme.Palette.control, in: shape)
        .overlay { shape.strokeBorder(isOn ? Theme.Palette.violet : Theme.Palette.hairline, lineWidth: 1) }
        .contentShape(shape)
        .onTapGesture(perform: action)
        .pointerStyle(.link)
        .accessibilityAddTraits(.isButton)
        .onHover { isHovering = $0 }
        .help(help)
    }

    private var icon: Image {
        switch row {
        case .ref(let ref): ref.kind == .tag ? Ph.tag : Ph.gitBranch
        case .commit: Ph.gitCommit
        }
    }

    private var title: String {
        switch row {
        case .ref(let ref): ref.name
        case .commit(let commit): commit.shortSHA
        }
    }

    /// What the chip has no room for: the commit's subject, and when.
    private var help: String {
        switch row {
        case .ref(let ref): ref.name
        case .commit(let commit): commit.subject
        }
    }
}
