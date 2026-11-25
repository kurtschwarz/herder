import Core
import DesignSystem
import SwiftUI
import TestSupport

/// The settings window's content: a sidebar of panes beside the one chosen.
///
/// Draws no backdrop and configures no window. Those are the composition
/// root's, which gives this the same glass and chrome as the main window.
public struct SettingsView: View {
    @State private var selection: SettingsPane = .general

    private let settings: UserSettingsStore
    private let openSettingsFile: () -> Void
    private let agents: AgentCatalog
    private let naming: NamingSettings
    private let version: AppVersion
    private let updater: (any UpdaterClient)?
    private let daemon: DaemonConnection?
    private let github: GitHubConnection?
    private let pullRequests: LinkedPullRequests?

    /// `openSettingsFile` opens `settings.json` in a main window's editor,
    /// which only the composition root can reach.
    public init(
        settings: UserSettingsStore, openSettingsFile: @escaping () -> Void,
        agents: AgentCatalog, naming: NamingSettings, version: AppVersion, updater: (any UpdaterClient)?, daemon: DaemonConnection?,
        github: GitHubConnection?, pullRequests: LinkedPullRequests? = nil
    ) {
        self.settings = settings
        self.openSettingsFile = openSettingsFile
        self.agents = agents
        self.naming = naming
        self.version = version
        self.updater = updater
        self.daemon = daemon
        self.github = github
        self.pullRequests = pullRequests
    }

    public var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection)
                .frame(width: Theme.Size.defaultSidebarWidth)
                .glassPaneBackground()
                .padding(Theme.Spacing.windowPadding)

            // Unpadded, unlike the sidebar, so a scrolling pane runs to the
            // window's edge and blurs out under its header there.
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.settingsFile, SettingsFile(problem: settings.problem, open: openSettingsFile))
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general: GeneralSettings(
                settings: settings, version: version, updater: updater, daemon: daemon, github: github, pullRequests: pullRequests
            )
        case .editor: EditorSettings(settings: settings)
        case .agents: AgentsSettings(catalog: agents)
        case .providers: ProvidersSettings(naming: naming)
        }
    }
}

#if DEBUG
#Preview {
    let settings = UserSettingsStore.inMemory()
    SettingsView(
        settings: settings,
        openSettingsFile: {},
        agents: AgentCatalog(state: InMemoryStateStore(), settings: settings),
        naming: NamingSettings(settings: settings, vault: InMemoryNamingKeyVault()),
        version: AppVersion(version: "0.1.0", build: "1", commit: "e87cd6e"),
        updater: StubUpdaterClient(),
        daemon: DaemonConnection(client: StubDaemonClient()),
        github: GitHubConnection(
            auth: StubGitHubAuthClient(), vault: InMemoryGitHubTokenVault(), daemon: StubDaemonClient(),
            clock: VirtualClockClient()
        )
    )
    .frame(width: Theme.Size.settingsWindow.width, height: Theme.Size.settingsWindow.height)
    .background { WindowGlass() }
    .preferredColorScheme(.dark)
}
#endif
