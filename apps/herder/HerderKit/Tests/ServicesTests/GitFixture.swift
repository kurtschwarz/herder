import Foundation
import Testing

/// Real repositories on disk, built with the real `git`, so the expected
/// answers come from git itself. Tests are not sandboxed, so running `git`
/// here is safe.
struct GitFixture {
    let directory: URL

    init(_ name: String) throws {
        directory = URL.temporaryDirectory.appending(path: "\(name)/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @discardableResult
    func git(_ arguments: String..., in url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = url
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            Issue.record("git \(arguments.joined(separator: " ")) failed: \(output)")
            throw CocoaError(.fileNoSuchFile)
        }
        return output
    }

    func makeDirectory(_ name: String) throws -> URL {
        let url = directory.appending(path: name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Who commits, and that they do not sign: a signing agent asked for dozens
    /// of signatures by a parallel run starts refusing.
    func configureIdentity(in url: URL) throws {
        try git("config", "user.email", "test@example.com", in: url)
        try git("config", "user.name", "Test", in: url)
        try git("config", "commit.gpgsign", "false", in: url)
    }

    func commitSomething(in url: URL) throws {
        try Data("x".utf8).write(to: url.appending(path: "README.md"))
        try git("add", ".", in: url)
        try git("commit", "-m", "first", in: url)
    }

    func makeRepository(_ name: String) throws -> URL {
        let url = try makeDirectory(name)
        try git("init", "--initial-branch=main", in: url)
        try configureIdentity(in: url)
        try commitSomething(in: url)
        return url
    }

    /// A bare repository with one commit on `main`, seeded through a clone.
    func seed(_ bare: URL, as name: String) throws {
        let seed = try makeDirectory("seed-\(name)")
        try git("clone", bare.path(percentEncoded: false), seed.path(percentEncoded: false), in: directory)
        try configureIdentity(in: seed)
        try commitSomething(in: seed)
        try git("push", "origin", "main", in: seed)
    }
}
