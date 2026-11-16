import Core
import DesignSystem
import SettingsFeature
import SwiftUI

/// The settings window: ``SettingsView`` on the same glass and chrome as a main
/// window, so its traffic lights sit in its sidebar header the same way.
public struct SettingsWindow: View {
    /// What the scene is declared under and what ⌘, opens.
    public static let id = "settings"

    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some View {
        SettingsView(
            agents: environment.agents,
            version: AppVersion(info: Bundle.main.infoDictionary ?? [:]),
            updater: environment.updater,
            daemon: environment.daemon
        )
            .background { WindowGlass() }
            // No close callbacks: nothing in here can be lost by closing it.
            // It is one window for the life of the app, so without following
            // the active Space ⌘, would jump back to the Space it first opened on.
            .background(WindowChrome(followsActiveSpace: true))
            .ignoresSafeArea()
            // Outside the safe area being ignored, not inside it. The window is
            // sized to this plus the title bar's safe area; inside, a fixed
            // frame would be shifted up into the title bar and leave a strip
            // of bare window its height along the bottom. Out here, what is
            // inside grows into the title bar instead and fills the window.
            .frame(width: Theme.Size.settingsWindow.width, height: Theme.Size.settingsWindow.height)
            .preferredColorScheme(.dark)
    }
}

#if DEBUG
#Preview {
    SettingsWindow(environment: .preview)
}
#endif
