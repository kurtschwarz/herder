import SwiftUI

/// What every pane's header needs to know about `settings.json`: how to open
/// it, and what is wrong with it, if anything.
///
/// Through the environment, so the header reaches it without each pane
/// passing it along.
struct SettingsFile {
    /// Why the file cannot be used. The settings in force meanwhile are the
    /// last good ones.
    var problem: String?

    /// Opens the file in the editor of the last main window used.
    var open: () -> Void
}

extension EnvironmentValues {
    @Entry var settingsFile: SettingsFile?
}
