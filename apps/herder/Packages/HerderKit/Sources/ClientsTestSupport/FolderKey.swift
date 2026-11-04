import Foundation

/// How the fakes in this module key a folder.
///
/// Two `URL`s can spell the same folder several ways. The fakes have to agree on
/// one spelling, or a test that seeds a folder one way and looks it up another
/// silently misses.
enum FolderKey {
    static func of(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }
}
