import Foundation

/// Where the Herder GitHub App lives on github.com.
public enum GitHubApp {
    /// Where a user installs the App on an account or repository. The slug is
    /// the one GitHub gives an App named `Herder`: see
    /// `docs/adr/0003-github-app-registration.md`.
    public static let installURL = URL(string: "https://github.com/apps/herder/installations/new")!
}
