import Core
import DesignSystem
import SwiftUI

/// The "From issue" modal, drawn over the whole window like the new-session
/// one, and for the same reason: the scrim has to cover both panes.
public struct IssueOverlay: View {
    private let model: RepositoriesModel

    @Environment(\.startAgentSession) private var startAgentSession
    @Environment(\.showAgentSession) private var showAgentSession
    @Environment(AgentCatalog.self) private var catalog: AgentCatalog?

    /// The agent the session starts with. Chosen afresh each time the modal
    /// opens, from the one used last.
    @State private var agentID: Agent.ID?

    public init(model: RepositoriesModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            if let issues = model.issueList {
                Theme.Palette.scrim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { if !issues.isStarting { model.cancelIssues() } }
                    .transition(.opacity)

                IssueCard(
                    model: issues,
                    github: model.github,
                    agents: catalog?.agents.filter(\.isRunnable) ?? [],
                    agentID: $agentID,
                    cancel: { model.cancelIssues() },
                    submit: {
                        let agent = agentID.flatMap { catalog?.agent($0) }
                        Task {
                            switch await model.submitIssue() {
                            case .resume(let session):
                                showAgentSession(session)
                            case .start(let worktree, let started):
                                startAgentSession(
                                    worktree, agent: agent, mode: .plan,
                                    prompt: started.prompt, name: started.title, issue: started.issue
                                )
                            case nil:
                                break
                            }
                        }
                    }
                )
                .onAppear { agentID = catalog?.lastUsed.id }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.issueList != nil)
    }
}

private struct IssueCard: View {
    let model: IssueListModel
    let github: GitHubConnection?
    let agents: [Agent]
    @Binding var agentID: Agent.ID?
    let cancel: () -> Void
    let submit: () -> Void

    @FocusState private var isSearchFocused: Bool

    /// Rows in view before the list scrolls.
    private static let visibleRows: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            header
            search
            tabs
            content
            if let line = model.refreshError ?? model.failure {
                Text(line)
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.warning)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(line)
            }
            if !agents.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
                    Text("Agent")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Palette.secondaryText)
                    agentChips
                }
            }
            buttons
        }
        .padding(Theme.Spacing.section)
        .frame(width: Theme.Size.wideModalWidth)
        .modalSurface()
        .task(id: ObjectIdentifier(model)) {
            isSearchFocused = true
            await model.load()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text("Implement an issue")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.Palette.text)
                Text("Open issues in \(model.repository ?? model.workspaceName). The agent drafts a plan first.")
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            Spacer(minLength: Theme.Spacing.loose)
            Button(action: cancel) {
                PhIcon(Ph.xBold, size: 12)
            }
            .buttonStyle(.icon(size: 24))
            .disabled(model.isStarting)
            .help("Close")
        }
    }

    // MARK: - Search

    private var search: some View {
        HStack(spacing: Theme.Spacing.normal) {
            PhIcon(Ph.magnifyingGlass, size: 14)
                .foregroundStyle(Theme.Palette.tertiaryText)
            TextField(
                "Search",
                text: Binding(get: { model.query }, set: { model.query = $0 }),
                prompt: Text("Search, or paste #123 or an issue link")
                    .foregroundStyle(Theme.Palette.tertiaryText)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.Palette.text)
            .focused($isSearchFocused)
            .onSubmit(submit)
            .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
            .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
            .onKeyPress(.escape) {
                guard !model.isStarting else { return .handled }
                cancel()
                return .handled
            }
            if model.isLookingUp {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
        .frame(minHeight: Theme.Size.control)
        .fieldSurface()
        .disabled(model.isStarting)
    }

    // MARK: - Tabs

    private var tabs: some View {
        HStack(spacing: Theme.Spacing.normal) {
            SegmentedToggle(
                GitHubIssueTab.allCases,
                selection: Binding(get: { model.tab }, set: { tab in Task { await model.show(tab) } }),
                title: { $0 == .assigned ? "Assigned to me" : "All open" },
                count: { model.count(for: $0) },
                hasNumberShortcuts: true
            )
            Spacer(minLength: 0)
            Button {
                Task { await model.refresh() }
            } label: {
                PhIcon(Ph.arrowClockwise, size: 14)
                    .rotationEffect(.degrees(model.isRefreshing ? 360 : 0))
                    .animation(
                        model.isRefreshing
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                        value: model.isRefreshing
                    )
            }
            .buttonStyle(.icon(size: 24))
            // Not disabled while spinning, so it keeps its hand: a press then does nothing.
            .disabled(model.isStarting)
            .help(model.updatedText)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let unavailable = model.unavailable {
            IssueUnavailable(unavailable: unavailable, github: github, retry: { Task { await model.load() } })
        } else if model.isLoading {
            note("Reading issues\u{2026}", spinning: true)
        } else if model.visibleIssues.isEmpty {
            note(emptyMessage)
        } else {
            list
        }
    }

    private var emptyMessage: String {
        if !model.query.isEmpty {
            if let missed = model.lookupMiss { return "There is no issue #\(missed) in \(model.repository ?? model.workspaceName)." }
            return IssueReference(parsing: model.query) != nil && model.isLookingUp
                ? "Looking for that issue\u{2026}" : "No issues match."
        }
        return model.tab == .assigned ? "Nothing is assigned to you." : "No open issues."
    }

    private func note(_ text: String, spinning: Bool = false) -> some View {
        HStack(spacing: Theme.Spacing.normal) {
            if spinning { ProgressView().controlSize(.small).scaleEffect(0.8) }
            Text(text)
                .font(.callout)
                .foregroundStyle(Theme.Palette.tertiaryText)
        }
        .frame(maxWidth: .infinity, minHeight: IssueRow.height * 2)
        .fieldGroupSurface()
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.visibleIssues) { issue in
                        IssueRow(
                            issue: issue,
                            session: model.session(for: issue),
                            isSelected: issue.number == model.selected?.number
                        ) {
                            model.select(issue.number)
                            isSearchFocused = true
                        } start: {
                            model.select(issue.number)
                            submit()
                        }
                        .id(issue.number)
                    }
                }
                .padding(Theme.Spacing.normal)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: Self.visibleRows * IssueRow.height)
            .fieldGroupSurface()
            .onChange(of: model.selected?.number) { _, number in
                guard let number else { return }
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(number) }
            }
        }
    }

    // MARK: - Agent

    private var agentChips: some View {
        FlowLayout {
            ForEach(agents) { agent in
                ChoiceChip(title: agent.displayName, isSelected: agent.id == agentID) {
                    AgentBadge(id: agent.type ?? agent.id, name: agent.displayName, size: 20)
                } action: { agentID = agent.id }
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: Theme.Spacing.normal) {
            Spacer(minLength: 0)

            Button("Cancel", action: cancel)
                .buttonStyle(.secondary)
                .disabled(model.isStarting)

            Button(action: submit) {
                ZStack {
                    Text(primaryLabel).opacity(model.isStarting ? 0 : 1)
                    if model.isStarting {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .buttonStyle(.primary)
            .disabled(model.selected == nil || model.isStarting)
        }
    }

    private var primaryLabel: String {
        if let issue = model.selected, model.session(for: issue) != nil { return "Open session \u{21B5}" }
        guard let name = agents.first(where: { $0.id == agentID })?.displayName else { return "Start \u{21B5}" }
        return "Start \(name) \u{21B5}"
    }
}

/// What the modal says in place of the list, and the one thing to do about it.
private struct IssueUnavailable: View {
    let unavailable: IssueListModel.Unavailable
    let github: GitHubConnection?
    let retry: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
            switch unavailable {
            case .notSignedIn:
                signIn

            case .notInstalled(let name):
                message("The Herder GitHub App isn\u{2019}t installed on \(name).")
                HStack(spacing: Theme.Spacing.normal) {
                    open("Install the app", GitHubApp.installURL)
                    again
                }

            case .permissionMissing(let name):
                message("Herder needs permission to read issues on \(name).")
                HStack(spacing: Theme.Spacing.normal) {
                    open("Review the installation", GitHubApp.installationSettingsURL(
                        owner: name.split(separator: "/").first.map(String.init) ?? name, login: login
                    ))
                    again
                }

            case .failed(let text):
                message(text)
                again
            }
        }
        .padding(Theme.Spacing.loose)
        .frame(maxWidth: .infinity, minHeight: IssueRow.height * 2, alignment: .leading)
        .fieldGroupSurface()
    }

    private var login: String? {
        if case .connected(let login)? = github?.state { login } else { nil }
    }

    private var again: some View {
        Button("Check again", action: retry)
            .buttonStyle(.secondary)
    }

    /// The one thing to do about it, on GitHub.
    private func open(_ title: String, _ url: URL) -> some View {
        Button(title) { openURL(url) }
            .buttonStyle(.primary)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Theme.Palette.text)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private var signIn: some View {
        if let github {
            switch github.state {
            case .signingIn(let code):
                message("Enter this code at github.com/login/device.")
                Text(code.userCode)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.Palette.text)
                    .textSelection(.enabled)
                HStack(spacing: Theme.Spacing.normal) {
                    open("Open github.com/login/device", code.verificationURL)
                    Button("Cancel") { github.cancelSignIn() }
                        .buttonStyle(.secondary)
                }
            case .checking:
                message("Checking your GitHub sign-in\u{2026}")
            case .connected:
                message("Signed in. Reading issues\u{2026}")
            default:
                message("Sign in to GitHub to see this repository\u{2019}s issues.")
                Button("Sign in with GitHub") {
                    Task {
                        await github.signIn()
                        if case .connected = github.state { retry() }
                    }
                }
                .buttonStyle(.primary)
                if let error = github.lastError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(Theme.Palette.warning)
                }
            }
        } else {
            message("GitHub isn\u{2019}t available in this build.")
        }
    }
}

private struct IssueRow: View {
    /// Tall enough for a title and a line under it, which is what the list's
    /// height is counted in.
    static let height: CGFloat = 56

    let issue: GitHubIssue
    let session: AgentSession?
    let isSelected: Bool
    let select: () -> Void
    let start: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
            Text("#\(issue.number)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.Palette.tertiaryText)
                .frame(minWidth: 40, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.Spacing.normal) {
                    Text(issue.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    ForEach(issue.labels.prefix(3), id: \.self) { LabelPill(label: $0) }
                }
                HStack(spacing: Theme.Spacing.normal) {
                    if let session {
                        Text("in progress \u{00B7} \(session.name ?? session.title)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.Palette.violet)
                            .lineLimit(1)
                    }
                    Text(details)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Theme.Spacing.normal)

            if issue.commentCount > 0 {
                HStack(spacing: 3) {
                    PhIcon(Ph.chatCenteredDots, size: 12)
                    Text("\(issue.commentCount)").font(.system(size: 11).monospacedDigit())
                }
                .foregroundStyle(Theme.Palette.tertiaryText)
            }
        }
        .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
        .frame(maxWidth: .infinity, minHeight: Self.height - 2, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous)
                .fill(isSelected ? Theme.Palette.violet.opacity(0.14) : isHovering ? Theme.Palette.control : .clear)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: start)
        .onTapGesture(perform: select)
        .pointerStyle(.link)
    }

    private var details: String {
        var parts: [String] = []
        if let author = issue.author { parts.append("@\(author)") }
        parts.append(RelativeAge.short(from: issue.updatedAt))
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// A label, in the colour GitHub gives it.
private struct LabelPill: View {
    let label: GitHubIssue.Label

    var body: some View {
        let color = Color(hex: label.color) ?? Theme.Palette.secondaryText
        Text(label.name)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background { Capsule().fill(color.opacity(0.16)) }
            .overlay { Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1) }
    }
}

extension Color {
    /// A colour from `rrggbb`, as GitHub spells a label's. `nil` for anything else.
    fileprivate init?(hex: String) {
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
