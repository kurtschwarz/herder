import Foundation

/// The opencode theme and plugin that Herder carries in its bundle, and how
/// they reach opencode.
///
/// opencode finds a theme only in a `themes` folder and a plugin only in a
/// `plugins` folder, or in `cli.json`'s `plugins`. That array replaces the
/// user's own when set inline, so `OPENCODE_CLI_CONFIG_CONTENT` cannot add
/// one. So each is linked into opencode's config folder from the bundle, the
/// way `just install` links it from a checkout. A link and not a copy, so
/// updating the app updates them.
public enum OpencodeIntegration {
    /// Each item's path under the bundle's `opencode` folder, which is also
    /// its path under opencode's config folder.
    public static let items = ["themes/herder.json", "plugins/osc-7501"]

    /// What is already at an item's place in the config folder.
    public enum Existing: Equatable, Sendable {
        case nothing
        /// A file or folder of the user's own.
        case item
        /// A link to `destination`, which `resolves` if it still exists.
        case link(destination: String, resolves: Bool)
    }

    /// Whether to put a link to the bundle where `existing` is.
    ///
    /// Anything of the user's is left alone, including a link to a checkout
    /// that `just install` made, so a developer's edits still reach opencode.
    /// A link into a Herder bundle is replaced: it is this app's own, from
    /// before an update or a move. So is a broken link, which serves nobody.
    public static func shouldLink(over existing: Existing) -> Bool {
        switch existing {
        case .nothing: true
        case .item: false
        case .link(let destination, let resolves): !resolves || destination.contains(bundleMarker)
        }
    }

    /// What every link into a Herder bundle's copy has in its path.
    static let bundleMarker = ".app/Contents/Resources/opencode/"
}
