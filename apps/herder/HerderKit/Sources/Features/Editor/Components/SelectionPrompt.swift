import Core
import DesignSystem
import SwiftUI

/// The small ⌘L hint that follows a selection. Clicking it is pressing ⌘L.
struct SelectionPill: View {
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Text("\u{2318}L")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.text)
                .padding(.horizontal, Theme.Spacing.normal)
                .frame(height: 20)
                .background(Theme.Palette.modal, in: Capsule())
                .overlay { Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .help("Send this selection to an agent")
    }
}

/// What a selection can be sent with: the lines it covers, which session gets
/// it, a question, and the canned ones.
struct SelectionPrompt: View {
    static let width: CGFloat = 460

    @Bindable var state: SelectionPromptState

    /// What this window has open. Absent outside a window.
    let open: WindowAgentSessions?
    let worktree: WorkspaceID?

    let send: (SelectionMessage.Action, AgentSession) -> Void
    let startSession: () -> Void
    let close: () -> Void

    @FocusState private var isFocused: Bool

    private var sessions: [AgentSession] {
        worktree.flatMap { open?.sessions(in: $0) } ?? []
    }

    private var target: AgentSession? {
        state.target(among: sessions, focused: open?.focused)
    }

    private var canSend: Bool {
        target.map(SelectionPromptState.accepts) ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.normal) {
            header
            field
            actions
        }
        .padding(Theme.Spacing.normal + Theme.Spacing.tight)
        .frame(width: Self.width)
        .background(Theme.Palette.modal, in: RoundedRectangle(cornerRadius: Theme.Radius.fieldGroup, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.fieldGroup, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .task { isFocused = true }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.normal) {
            HStack(spacing: Theme.Spacing.tight) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                Text(summary)
            }
            .foregroundStyle(Theme.Palette.secondaryText)
            Text("to").foregroundStyle(Theme.Palette.tertiaryText)
            chip
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
    }

    private var summary: String {
        let lines = state.ref.lineCount
        return "\(lines) \(lines == 1 ? "line" : "lines")\(state.ref.isPartial ? " (partial)" : "")"
    }

    @ViewBuilder
    private var chip: some View {
        if sessions.isEmpty {
            Button("Start session\u{2026}", action: startSession)
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Palette.accent)
        } else {
            Menu {
                ForEach(sessions) { session in
                    Button {
                        state.chosen = session.id
                    } label: {
                        Text(session.name ?? session.title)
                    }
                }
            } label: {
                HStack(spacing: Theme.Spacing.tight) {
                    AgentStateDot(target?.state ?? .idle)
                    Text(target.map { $0.name ?? $0.title } ?? "")
                        .lineLimit(1)
                        .foregroundStyle(Theme.Palette.text)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.normal) {
            TextField("Ask the agent about this\u{2026}", text: $state.feedback, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isFocused)
                .onKeyPress(.return, phases: .down) { press in
                    // A newline is Shift+Return's, which the field takes.
                    if press.modifiers.contains(.shift) { return .ignored }
                    submit(press.modifiers.contains(.command) ? .addToContext : .send)
                    return .handled
                }
            Button {
                submit(.send)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Palette.onViolet)
                    .frame(width: 24, height: 24)
                    .background(Theme.Palette.violet, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.4)
            .help("Send (Return)")
        }
        .padding(Theme.Spacing.normal)
        .background(Theme.Palette.field, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.tight) {
            quick("Explain", .explain)
            quick("Fix", .fix)
            quick("Write tests", .writeTests)
            Spacer(minLength: 0)
            Button {
                submit(.addToContext)
            } label: {
                HStack(spacing: Theme.Spacing.tight) {
                    Text("+ Add to context")
                    Text("\u{2318}\u{21A9}").foregroundStyle(Theme.Palette.tertiaryText)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Palette.secondaryText)
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.4)
        }
        .font(.system(size: 12))
    }

    private func quick(_ title: String, _ action: SelectionMessage.Action) -> some View {
        Button(title) { submit(action) }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.normal)
            .frame(height: 22)
            .background(Theme.Palette.control, in: Capsule())
            .foregroundStyle(Theme.Palette.text)
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.4)
    }

    private func submit(_ action: SelectionMessage.Action) {
        guard canSend, let target else { return }
        send(action, target)
    }
}
