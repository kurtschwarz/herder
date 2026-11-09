import Foundation

/// Where the running copy of Herder is, as far as anything it writes outside
/// itself is concerned.
///
/// A copy opened straight from the disk image, or from Downloads without being
/// moved, is not one to point anything at. The image goes when it is ejected.
/// Gatekeeper runs a downloaded app that has not been moved from a random,
/// read-only copy of itself (App Translocation), at a path that changes from
/// one launch to the next. A link made into either is dangling by the next
/// launch.
public enum AppLocation: Equatable, Sendable {
    /// Somewhere it stays: `/Applications`, `~/Applications`, or a build
    /// folder.
    case settled
    /// A translocated copy of a download that has not been moved.
    case translocated
    /// A mounted disk image.
    case diskImage

    /// Read off the bundle's path alone. A translocated copy always sits
    /// under an `AppTranslocation` folder, and a disk image is mounted under
    /// `/Volumes`. So is any other drive, so an app kept on one counts as a
    /// disk image too. It gets asked to move each launch, and nothing worse.
    public init(bundle: URL) {
        let path = bundle.standardizedFileURL.path(percentEncoded: false)
        if path.contains("/AppTranslocation/") {
            self = .translocated
        } else if path.hasPrefix("/Volumes/") {
            self = .diskImage
        } else {
            self = .settled
        }
    }
}
