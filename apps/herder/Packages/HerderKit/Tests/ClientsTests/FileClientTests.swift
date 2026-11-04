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
