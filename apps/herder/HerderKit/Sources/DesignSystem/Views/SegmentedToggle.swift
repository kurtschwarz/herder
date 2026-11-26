import SwiftUI

/// A switch between a few options, one always on: a recessed track with a
/// pill that slides to the chosen one. Each option may carry a count, and the
/// first nine can answer to ⌘1 to ⌘9.
public struct SegmentedToggle<Option: Hashable>: View {
    private let options: [Option]
    private let selection: Binding<Option>
    private let title: (Option) -> String
    private let count: (Option) -> Int?
    private let hasNumberShortcuts: Bool

    @Namespace private var pill

    public init(
        _ options: [Option],
        selection: Binding<Option>,
        title: @escaping (Option) -> String,
        count: @escaping (Option) -> Int? = { _ in nil },
        hasNumberShortcuts: Bool = false
    ) {
        self.options = options
        self.selection = selection
        self.title = title
        self.count = count
        self.hasNumberShortcuts = hasNumberShortcuts
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(3)
        .frame(height: Theme.Size.control)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.Palette.control)
        }
        .fixedSize()
        .pointerStyle(.link)
        .background { if hasNumberShortcuts { shortcuts } }
    }

    /// Out of sight: the segments have no visible key to show.
    private var shortcuts: some View {
        HStack {
            ForEach(Array(options.prefix(9).enumerated()), id: \.offset) { index, option in
                Button("") { selection.wrappedValue = option }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = selection.wrappedValue == option
        return Button {
            guard !isSelected else { return }
            withAnimation(.easeOut(duration: 0.15)) { selection.wrappedValue = option }
        } label: {
            HStack(spacing: Theme.Spacing.tight + 2) {
                Text(title(option))
                    .font(.system(size: 12, weight: .medium))
                if let count = count(option) {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(isSelected ? Theme.Palette.secondaryText : Theme.Palette.tertiaryText)
                }
            }
            .foregroundStyle(isSelected ? Theme.Palette.text : Theme.Palette.secondaryText)
            .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
            .frame(maxHeight: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.control - 3, style: .continuous)
                        .fill(Theme.Palette.controlPressed)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
private struct SegmentedTogglePreview: View {
    @State private var selection = "open"

    var body: some View {
        SegmentedToggle(
            ["assigned", "open"], selection: $selection,
            title: { $0 == "open" ? "All open" : "Assigned to me" },
            count: { $0 == "open" ? 12 : 3 }
        )
        .padding()
        .background(Theme.Palette.modal)
    }
}

#Preview {
    SegmentedTogglePreview()
}
#endif
