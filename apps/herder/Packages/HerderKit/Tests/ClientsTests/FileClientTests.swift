import Clients
import ClientsTestSupport
import Foundation
import Testing

/// Hits the real file system, so each test gets its own directory. Swift Testing
/// runs tests in parallel and a shared path would make them flake.
@Suite struct LiveFileClientTests {
    let directory: URL
    let client = LiveFileClient()

    init() throws {
        directory = URL.temporaryDirectory
            .appending(path: "LiveFileClientTests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func path(_ name: String) -> String {
        directory.appending(path: name).path(percentEncoded: false)
    }

    @Test func writesThenReadsBack() async throws {
        try await client.write("hello", to: path("a.txt"))
        #expect(try await client.read(path("a.txt")) == "hello")
    }

    @Test func readingAMissingPathThrows() async {
        let missing = path("nope.txt")
        await #expect(throws: FileClientError.notFound(path: missing)) {
            try await client.read(missing)
        }
    }

    @Test func listsWhatIsInsideAFolder() async throws {
        try await client.write("x", to: path("a.txt"))
        try FileManager.default.createDirectory(at: directory.appending(path: "sub"), withIntermediateDirectories: true)

        let children = try await client.children(of: directory)

        #expect(children.map(\.name).sorted() == ["a.txt", "sub"])
        #expect(children.first { $0.name == "sub" }?.isDirectory == true)
        #expect(children.first { $0.name == "a.txt" }?.isDirectory == false)
    }

    @Test func aLinkToAFolderReadsAsAFolder() async throws {
        let target = directory.appending(path: "target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: directory.appending(path: "link"), withDestinationURL: target)

        let children = try await client.children(of: directory)

        #expect(children.first { $0.name == "link" }?.isDirectory == true)
    }

    @Test func listingAMissingFolderThrows() async {
        let missing = directory.appending(path: "nope")
        await #expect(throws: FileClientError.unreadable(path: missing.path(percentEncoded: false))) {
            try await client.children(of: missing)
        }
    }

    @Test func movingRenamesOnDisk() async throws {
        try await client.write("x", to: path("a.txt"))

        try await client.move(directory.appending(path: "a.txt"), to: directory.appending(path: "b.txt"))

        #expect(await !client.exists(path("a.txt")))
        #expect(try await client.read(path("b.txt")) == "x")
    }

    @Test func movingOntoAnExistingNameThrowsAndKeepsBoth() async throws {
        try await client.write("a", to: path("a.txt"))
        try await client.write("b", to: path("b.txt"))

        await #expect(throws: FileClientError.alreadyExists(path: path("b.txt"))) {
            try await client.move(directory.appending(path: "a.txt"), to: directory.appending(path: "b.txt"))
        }
        #expect(try await client.read(path("b.txt")) == "b")
    }

    @Test func movingCanOnlyChangeCase() async throws {
        try await client.write("x", to: path("a.txt"))

        try await client.move(directory.appending(path: "a.txt"), to: directory.appending(path: "A.txt"))

        let names = try await client.children(of: directory).map(\.name)
        #expect(names == ["A.txt"])
    }

    @Test func createsAnEmptyFileAndAFolder() async throws {
        try await client.create(directory.appending(path: "a.txt"), isDirectory: false)
        try await client.create(directory.appending(path: "sub"), isDirectory: true)

        #expect(try await client.read(path("a.txt")) == "")
        let children = try await client.children(of: directory)
        #expect(children.first { $0.name == "sub" }?.isDirectory == true)
    }

    @Test func creatingOverAnExistingNameThrowsAndKeepsIt() async throws {
        try await client.write("keep", to: path("a.txt"))

        await #expect(throws: FileClientError.alreadyExists(path: path("a.txt"))) {
            try await client.create(directory.appending(path: "a.txt"), isDirectory: false)
        }
        #expect(try await client.read(path("a.txt")) == "keep")
    }

    @Test func writeCreatesIntermediateDirectories() async throws {
        try await client.write("deep", to: path("one/two/three.txt"))
        #expect(try await client.read(path("one/two/three.txt")) == "deep")
    }
}

/// The fake has to behave like the real thing, or tests written against it lie.
@Suite struct InMemoryFileClientTests {
    let client = InMemoryFileClient()

    @Test func seededPathsAreReadable() async throws {
        client.seed("/tmp/a.txt", "seeded")
        #expect(try await client.read("/tmp/a.txt") == "seeded")
    }

    @Test func readingAMissingPathThrows() async {
        await #expect(throws: FileClientError.notFound(path: "/tmp/missing")) {
            try await client.read("/tmp/missing")
        }
    }

    @Test func existsReflectsWrites() async throws {
        #expect(await client.exists("/tmp/b.txt") == false)
        try await client.write("x", to: "/tmp/b.txt")
        #expect(await client.exists("/tmp/b.txt"))
    }
}
