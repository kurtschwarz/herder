import Core
import Foundation
import Testing

@Suite struct PathKeyTests {
    @Test func aTrailingSlashIsNotPartOfTheKey() {
        #expect(PathKey(canonical: "/code/api/") == PathKey(canonical: "/code/api"))
        #expect(PathKey(canonical: "/code/api///").path == "/code/api")
    }

    @Test func theVolumeRootKeepsItsSlash() {
        #expect(PathKey(canonical: "/").path == "/")
    }

    /// The case this type exists for: a bookmark keeps the path the user picked,
    /// while git and the watcher both hand back the resolved one, and the two
    /// are not equal until something resolves them. `standardizedFileURL`,
    /// which the rest of the app reaches for, is not enough: it strips `.` and
    /// `..` and leaves symlinks alone.
    @Test func aPathThroughASymlinkResolvesToTheSameKey() throws {
        let directory = URL.temporaryDirectory.appending(path: "PathKeyTests/\(UUID().uuidString)")
        let real = directory.appending(path: "real")
        let link = directory.appending(path: "link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(PathKey(link.appending(path: "a.txt")) == PathKey(real.appending(path: "a.txt")))
        #expect(link.standardizedFileURL != real.standardizedFileURL)
    }

    /// The divergence that makes a trusted key dangerous. FSEvents reports
    /// `/private/var/folders/…`; `resolvingSymlinksInPath()` goes the other way
    /// and strips the `/private`, so the canonical form is `/var/folders/…` and
    /// the system's own spelling is not it.
    @Test func aPathTheSystemReportsWithAPrivatePrefixCanonicalisesToTheSameKey() throws {
        let canonical = PathKey(URL.temporaryDirectory)
        let asReported = "/private" + canonical.path
        try #require(FileManager.default.fileExists(atPath: asReported))

        #expect(PathKey(URL(filePath: asReported)) == canonical)
        // And trusting it would have silently produced a key matching nothing.
        #expect(PathKey(canonical: asReported) != canonical)
    }

    @Test func appendingJoinsWithoutResolvingAnything() {
        let root = PathKey(canonical: "/code/api")

        #expect(root.appending("Sources/App.swift").path == "/code/api/Sources/App.swift")
        #expect(PathKey(canonical: "/").appending("etc").path == "/etc")
    }

    @Test func theParentIsTheFolderAboveAndRunsOutAtTheVolumeRoot() {
        #expect(PathKey(canonical: "/code/api/a.txt").parent == PathKey(canonical: "/code/api"))
        #expect(PathKey(canonical: "/code").parent == PathKey(canonical: "/"))
        #expect(PathKey(canonical: "/").parent == nil)
    }

    @Test func theNameIsTheLastComponent() {
        #expect(PathKey(canonical: "/code/api/a.txt").name == "a.txt")
        #expect(PathKey(canonical: "/code").name == "code")
    }

    @Test func aKeyIsInsideItselfAndEveryFolderAboveIt() {
        let path = PathKey(canonical: "/code/api/Sources/App.swift")

        #expect(path.isInside(path))
        #expect(path.isInside(PathKey(canonical: "/code/api")))
        #expect(path.isInside(PathKey(canonical: "/")))
        #expect(!path.isInside(PathKey(canonical: "/code/apifoo")))
        #expect(!path.isInside(PathKey(canonical: "/elsewhere")))
    }

    @Test func parentsRunNearestFirstAndStopAtTheRoot() {
        let root = PathKey(canonical: "/code/api")
        let path = root.appending("Sources/deep/App.swift")

        #expect(path.parents(upTo: root) == [
            root.appending("Sources/deep"), root.appending("Sources"), root,
        ])
    }

    @Test func aKeyHasNoParentsBelowItselfOrOutsideTheRoot() {
        let root = PathKey(canonical: "/code/api")

        #expect(root.parents(upTo: root).isEmpty)
        #expect(PathKey(canonical: "/elsewhere/a.txt").parents(upTo: root).isEmpty)
    }

    @Test func theUrlRoundTripsWithoutATrailingSlash() {
        #expect(PathKey(canonical: "/code/api/").url.path(percentEncoded: false) == "/code/api")
    }
}
