import Foundation

/// Where the Herder GitHub App lives on github.com.
public enum GitHubApp {
    /// Where a user installs the App on an account or repository. The App's
    /// slug is `herder-app`: see `docs/adr/0003-github-app-registration.md`.
    public static let installURL = URL(string: "https://github.com/apps/herder-app/installations/new")!

    /// Where to review what the App may read on `owner`'s installation: the
    /// user's own settings when `owner` is the signed-in `login`, the
    /// organisation's otherwise.
    public static func installationSettingsURL(owner: String, login: String?) -> URL {
        if let login, login.caseInsensitiveCompare(owner) == .orderedSame {
            return URL(string: "https://github.com/settings/installations")!
        }
        let escaped = owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? owner
        return URL(string: "https://github.com/organizations/\(escaped)/settings/installations")!
    }
}
