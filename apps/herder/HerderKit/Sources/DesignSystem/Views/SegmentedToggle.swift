import SwiftUI

/// A switch between a few options, one always on: a recessed track with a
/// pill that slides to the chosen one. Each option may carry a count.
public struct SegmentedToggle<Option: Hashable>: View {
    private let options: [Option]
    private let selection: Binding<Option>
    private let title: (Option) -> String
    private let count: (Option) -> Int?

    @Namespace private var pill

    public init(
        _ options: [Option],
        selection: Binding<Option>,
        title: @escaping (Option) -> String,
        count: @escaping (Option) -> Int? = { _ in nil }
    ) {
        self.options = options
        self.selection = selection
        self.title = title
        self.count = count
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.Palette.field)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                }
        }
        .fixedSize()
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = selection.wrappedValue == option
        return Button {
            guard !isSelected else { return }
            withAnimation(.easeOut(duration: 0.15)) { selection.wrappedValue = option }
        } label: {
            HStack(spacing: Theme.Spacing.tight + 2) {
                Text(title(option))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                if let count = count(option) {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .padding(.horizontal, Theme.Spacing.normal - 2)
                        .padding(.vertical, 1)
                        .background { Capsule().fill(Theme.Palette.control) }
                }
            }
            .foregroundStyle(isSelected ? Theme.Palette.text : Theme.Palette.secondaryText)
            .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
            .frame(minHeight: 24)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.control - 2, style: .continuous)
                        .fill(Theme.Palette.violet.opacity(0.18))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.control - 2, style: .continuous)
                                .strokeBorder(Theme.Palette.violet.opacity(0.6), lineWidth: 1)
                        }
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
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
