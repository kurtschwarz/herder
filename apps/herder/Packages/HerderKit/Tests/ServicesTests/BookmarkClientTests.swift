import Core
import Foundation
import Services
import TestSupport
import Testing

/// Makes real bookmarks against real folders. The test bundle is not sandboxed,
/// so the security scope is inert here; what this suite pins down is the
/// round trip and the failure modes, which are the same either way.
@Suite struct LiveBookmarkClientTests {
    let directory: URL
    let client = LiveBookmarkClient()

    init() throws {
        directory = URL.temporaryDirectory
            .appending(path: "LiveBookmarkClientTests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test func resolvesBackToTheSameFolder() throws {
        let bookmark = try client.makeBookmark(for: directory)
        let resolved = try client.resolve(bookmark)
        #expect(resolved.url.resolvingSymlinksInPath() == directory.resolvingSymlinksInPath())
    }

    @Test func followsTheFolderAcrossARename() throws {
        let original = directory.appending(path: "before")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        let bookmark = try client.makeBookmark(for: original)

        let renamed = directory.appending(path: "after")
        try FileManager.default.moveItem(at: original, to: renamed)

        let resolved = try client.resolve(bookmark)
        #expect(resolved.url.resolvingSymlinksInPath() == renamed.resolvingSymlinksInPath())
    }

    @Test func makingABookmarkForAMissingFolderThrows() {
        #expect(throws: (any Error).self) {
            try client.makeBookmark(for: directory.appending(path: "nothing-here"))
        }
    }

    @Test func resolvingNonsenseThrows() {
        #expect(throws: (any Error).self) {
            try client.resolve(Data("not a bookmark".utf8))
        }
    }
}

/// The fake has to behave like the real thing, or tests written against it lie.
@Suite struct InMemoryBookmarkClientTests {
    let client = InMemoryBookmarkClient()
    let url = URL(filePath: "/tmp/InMemoryBookmarkClientTests/repo")

    @Test func resolvesBackToTheSameFolder() throws {
        let bookmark = try client.makeBookmark(for: url)
        let resolved = try client.resolve(bookmark)
        #expect(resolved.url == url)
        #expect(resolved.isStale == false)
    }

    @Test func resolvingAnUnknownBookmarkThrows() {
        #expect(throws: BookmarkClientError.unresolvable) {
            try client.resolve(Data("unknown".utf8))
        }
    }

    @Test func foldersCanBeMadeUnresolvable() throws {
        let bookmark = try client.makeBookmark(for: url)
        client.breakResolution(for: url)
        #expect(throws: BookmarkClientError.unresolvable) {
            try client.resolve(bookmark)
        }
    }

    @Test func foldersCanBeMadeStale() throws {
        let bookmark = try client.makeBookmark(for: url)
        client.markStale(url)
        #expect(try client.resolve(bookmark).isStale)
    }

    @Test func recordsWhichFoldersAreBeingAccessed() throws {
        #expect(client.startAccessing(url))
        #expect(client.accessedURLs == [url])
        client.stopAccessing(url)
        #expect(client.accessedURLs.isEmpty)
    }
}
