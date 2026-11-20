import Core
import DesignSystem
import SwiftUI

/// The card pinned over the sidebar's list: type what to build, and Plan it
/// starts the last-used agent in plan mode, in a fresh worktree named for it.
/// The terminal icon opens the new-session modal, which is how an existing
/// worktree is picked or a build session started.
struct NewOrderCard: View {
    let model: RepositoriesModel

    @Environment(Workspace.self) private var active: Workspace?
    @Environment(\.startAgentSession) private var startAgentSession

    private var order: NewOrderModel { model.order }

    private var repository: Repository? {
        model.orderRepository(active: active?.id.url)
    }

    private var canPlan: Bool { order.canSubmit && repository != nil }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.normal) {
            header
            input
            actions
            Text("The agent drafts a plan first. Nothing gets built until you approve it.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let failure = order.failure {
                Text(failure)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(Theme.Spacing.normal + Theme.Spacing.tight)
        .background(Theme.Palette.fieldGroup, in: shape)
        .overlay { shape.strokeBorder(Theme.Palette.hairline, lineWidth: 1) }
        .padding(.horizontal, Theme.Spacing.windowPadding)
        .padding(.bottom, Theme.Spacing.normal)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: Theme.Spacing.tight + 2) {
            PhIcon(Ph.clipboardText, size: 14)
                .foregroundStyle(Theme.Palette.violet)
            Text("New order")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.text)
                .lineLimit(1)
                .fixedSize()
            Text("\u{2325}\u{2318}N")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.Palette.secondaryText)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Theme.Palette.control, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .fixedSize()
            Text("in")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.secondaryText)
            WorkspaceSelector(
                model: model,
                selection: .single(Binding(
                    get: { repository?.id },
                    set: { id in order.pick(model.repositories.first { $0.id == id }) }
                )),
                isInline: true
            )
            .layoutPriority(-1)
            Spacer(minLength: 0)
            Button { openModal() } label: {
                PhIcon(Ph.terminal, size: 14)
            }
            .buttonStyle(.icon(size: 22))
            .disabled(repository == nil)
            .help("Pick a worktree, or start a build session\u{2026}")
        }
    }

    private var input: some View {
        NewOrderInput(order: order, canPlan: canPlan, plan: plan)
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.normal) {
            Button {} label: {
                Text("From issue")
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Palette.secondaryText)
            .disabled(true)
            .opacity(0.5)
            .help("Coming soon")

            Spacer(minLength: 0)

            Button(action: plan) {
                HStack(spacing: Theme.Spacing.tight) {
                    if order.isWorking {
                        ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                    }
                    Text("Plan it \u{21B5}").lineLimit(1).fixedSize()
                }
            }
            .buttonStyle(PlanButtonStyle())
            .disabled(!canPlan)
        }
    }

    // MARK: - Actions

    private func plan() {
        guard canPlan else { return }
        let activeURL = active?.id.url
        Task {
            guard let result = await model.submitOrder(active: activeURL) else { return }
            startAgentSession(
                result.worktree, mode: .plan, prompt: result.started.prompt, name: result.started.title
            )
        }
    }

    private func openModal() {
        guard let repository else { return }
        model.beginNewSession(in: repository, active: active?.id.url, mode: .build)
    }
}

/// The primary plate at a size that fits a sidebar.
private struct PlanButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.Palette.onViolet)
            .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
            .frame(minHeight: Theme.Size.control - 6)
            .background(
                Theme.Palette.violet.opacity(configuration.isPressed ? 0.8 : 1),
                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            )
            .pointerStyle(isEnabled ? .link : nil)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// The text field alone. It is the only view that reads what was typed, so a
/// keystroke redraws it and nothing else.
private struct NewOrderInput: View {
    @Bindable var order: NewOrderModel
    let canPlan: Bool
    let plan: () -> Void

    @FocusState private var isTyping: Bool

    var body: some View {
        TextField("What should we build next?", text: $order.text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.Palette.text)
            .lineLimit(1...4)
            .focused($isTyping)
            .disabled(order.isWorking)
            .padding(.horizontal, Theme.Spacing.normal)
            .padding(.vertical, Theme.Spacing.normal - 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fieldSurface()
            .onKeyPress(phases: .down) { press in
                guard press.key == .return else { return .ignored }
                if press.modifiers.contains(.shift) {
                    order.text += "\n"
                } else if canPlan {
                    plan()
                }
                return .handled
            }
            .onChange(of: order.focusRequest) { isTyping = true }
    }
}
