import Foundation
import Clients
import Testing

@Suite struct GitRefNameTests {
    @Test(arguments: ["main", "agent/add-minimap", "fix_1.2", "v1.0", "a/b/c", "feature-x", "ünï"])
    func acceptsOrdinaryNames(name: String) {
        #expect(GitRefName.problem(in: name) == nil)
    }

    @Test func refusesAnEmptyName() {
        #expect(GitRefName.problem(in: "") == .empty)
    }

    @Test(arguments: [
        "-leading", "@", "/lead", "trail/", "a//b", "a..b", "a@{b", "ends.", "has space",
        "a~b", "a^b", "a:b", "a?b", "a*b", "a[b", "a\\b", ".hidden", "a/.hidden", "a.lock", "a/b.lock",
        "tab\there",
    ])
    func refusesNamesGitWouldRefuse(name: String) {
        #expect(GitRefName.problem(in: name) != nil)
    }

    @Test func agreesWithGit() throws {
        // The rules are re-implemented so a name can be checked while it is
        // typed; this pins them to `git check-ref-format` for a spread of cases.
        // A leading dash and a lone @ are not among them: those rules are
        // `git branch`'s, not the ref format's.
        let names = ["main", "a/b", "a..b", "a b", "a.lock", "a/.b", "a@{b", "x/", "ok-1.2"]
        for name in names {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/git")
            process.arguments = ["check-ref-format", "refs/heads/\(name)"]
            process.standardError = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            #expect((process.terminationStatus == 0) == (GitRefName.problem(in: name) == nil), "\(name)")
        }
    }
}
