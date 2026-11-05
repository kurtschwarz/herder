import Foundation
import Models
import Testing

@Suite struct PathKeyTests {
    @Test func aTrailingSlashIsNotPartOfTheKey() {
        #expect(PathKey(resolved: "/code/api/") == PathKey(resolved: "/code/api"))
        #expect(PathKey(resolved: "/code/api///").path == "/code/api")
    }

    @Test func theVolumeRootKeepsItsSlash() {
        #expect(PathKey(resolved: "/").path == "/")
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

    @Test func appendingJoinsWithoutResolvingAnything() {
        let root = PathKey(resolved: "/code/api")

        #expect(root.appending("Sources/App.swift").path == "/code/api/Sources/App.swift")
        #expect(PathKey(resolved: "/").appending("etc").path == "/etc")
    }

    @Test func theParentIsTheFolderAboveAndRunsOutAtTheVolumeRoot() {
        #expect(PathKey(resolved: "/code/api/a.txt").parent == PathKey(resolved: "/code/api"))
        #expect(PathKey(resolved: "/code").parent == PathKey(resolved: "/"))
        #expect(PathKey(resolved: "/").parent == nil)
    }

    @Test func theNameIsTheLastComponent() {
        #expect(PathKey(resolved: "/code/api/a.txt").name == "a.txt")
        #expect(PathKey(resolved: "/code").name == "code")
    }

    @Test func aKeyIsInsideItselfAndEveryFolderAboveIt() {
        let path = PathKey(resolved: "/code/api/Sources/App.swift")

        #expect(path.isInside(path))
        #expect(path.isInside(PathKey(resolved: "/code/api")))
        #expect(path.isInside(PathKey(resolved: "/")))
        #expect(!path.isInside(PathKey(resolved: "/code/apifoo")))
        #expect(!path.isInside(PathKey(resolved: "/elsewhere")))
    }

    @Test func parentsRunNearestFirstAndStopAtTheRoot() {
        let root = PathKey(resolved: "/code/api")
        let path = root.appending("Sources/deep/App.swift")

        #expect(path.parents(upTo: root) == [
            root.appending("Sources/deep"), root.appending("Sources"), root,
        ])
    }

    @Test func aKeyHasNoParentsBelowItselfOrOutsideTheRoot() {
        let root = PathKey(resolved: "/code/api")

        #expect(root.parents(upTo: root).isEmpty)
        #expect(PathKey(resolved: "/elsewhere/a.txt").parents(upTo: root).isEmpty)
    }

    @Test func theUrlRoundTripsWithoutATrailingSlash() {
        #expect(PathKey(resolved: "/code/api/").url.path(percentEncoded: false) == "/code/api")
    }
}
