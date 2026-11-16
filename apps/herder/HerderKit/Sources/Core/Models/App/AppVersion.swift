import Foundation

/// Which build of Herder this is, as its Info.plist records it.
///
/// A release gets its version from its tag and its build number from the
/// commit count. `scripts/package.sh` stamps both and the commit, and fails
/// if the plist does not then say so. A build from Xcode or `just build` has
/// whatever `project.yml` says, which Release Please keeps at the last
/// release.
public struct AppVersion: Equatable, Sendable {
    /// `CFBundleShortVersionString`, e.g. `0.1.0`.
    public var version: String
    /// `CFBundleVersion`.
    public var build: String
    /// The short hash of the commit it was built from, when the build said.
    public var commit: String?

    /// The Info.plist key the commit is under.
    public static let commitKey = "HerderGitCommit"

    public init(version: String, build: String, commit: String? = nil) {
        self.version = version
        self.build = build
        self.commit = commit
    }

    /// Read from a bundle's `infoDictionary`. An empty commit is a build that
    /// did not set one.
    public init(info: [String: Any]) {
        self.version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        self.build = info["CFBundleVersion"] as? String ?? "unknown"
        self.commit = (info[Self.commitKey] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `0.1.0 (42)`, the way the Finder and About windows show a version.
    public var display: String {
        "\(version) (\(build))"
    }
}
