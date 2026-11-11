import Foundation
import Testing

@testable import Core

@Suite struct TerminalLinkDetectorTests {
    func found(_ text: String) -> [TerminalLinkCandidate] {
        TerminalLinkDetector.candidates(in: text)
    }

    func urls(_ text: String) -> [String] {
        found(text).compactMap {
            if case .url(let url) = $0.kind { url.absoluteString } else { nil }
        }
    }

    func paths(_ text: String) -> [TerminalPathReference] {
        found(text).compactMap {
            if case .path(let reference) = $0.kind { reference } else { nil }
        }
    }

    func text(_ candidate: TerminalLinkCandidate, in text: String) -> String {
        let units = Array(text.utf16)
        return String(decoding: units[candidate.range], as: UTF16.self)
    }

    // MARK: URLs

    @Test func aUrlInTextIsFoundWithItsRange() {
        let line = "see https://example.com/a/b for more"
        let candidates = found(line)
        #expect(candidates.count == 1)
        #expect(text(candidates[0], in: line) == "https://example.com/a/b")
    }

    @Test func trailingPunctuationIsNotPartOfAUrl() {
        #expect(urls("go to https://x.y/z.") == ["https://x.y/z"])
        #expect(urls("https://x.y/z, then") == ["https://x.y/z"])
        #expect(urls("really https://x.y/z?!") == ["https://x.y/z"])
        #expect(urls("\"https://x.y/z\"") == ["https://x.y/z"])
    }

    @Test func anUnbalancedBracketIsNotPartOfAUrl() {
        #expect(urls("(see https://x.y/z).") == ["https://x.y/z"])
        #expect(urls("[https://x.y/z]") == ["https://x.y/z"])
        #expect(urls("<https://x.y/z>") == ["https://x.y/z"])
    }

    @Test func aBalancedBracketBelongsToTheUrl() {
        #expect(urls("https://en.wikipedia.org/wiki/Swift_(language)") == ["https://en.wikipedia.org/wiki/Swift_(language)"])
        #expect(urls("(https://en.wikipedia.org/wiki/Swift_(language))") == ["https://en.wikipedia.org/wiki/Swift_(language)"])
    }

    @Test func severalUrlsOnALineAreAllFound() {
        #expect(urls("http://a.io and https://b.io/x") == ["http://a.io", "https://b.io/x"])
    }

    @Test func otherSchemesTheDetectorKnowsAreFound() {
        #expect(urls("write to mailto:kurt@example.com today") == ["mailto:kurt@example.com"])
    }

    @Test func aBareDomainOrAFileNameIsNotAUrl() {
        #expect(urls("README.md and example.com").isEmpty)
    }

    @Test func aUrlWithNoHostIsNotAUrl() {
        #expect(urls("see https:// there").isEmpty)
    }

    // MARK: Paths

    @Test func relativeAbsoluteAndHomePathsAreFound() {
        let line = "src/foo.swift ./a/b.ts /abs/path ~/x ../up/file.md"
        #expect(paths(line).map(\.path) == ["src/foo.swift", "./a/b.ts", "/abs/path", "~/x", "../up/file.md"])
    }

    @Test func aPathCarriesItsLineAndColumn() {
        let line = "at path/to/file.swift:42:7 here"
        let candidates = found(line)
        #expect(paths(line) == [TerminalPathReference(path: "path/to/file.swift", line: 42, column: 7)])
        #expect(text(candidates[0], in: line) == "path/to/file.swift:42:7")
    }

    @Test func aPathWithOnlyALineHasNoColumn() {
        #expect(paths("src/a.swift:9") == [TerminalPathReference(path: "src/a.swift", line: 9, column: nil)])
    }

    @Test func aPathWithNoLocationHasNeither() {
        #expect(paths("src/a.swift") == [TerminalPathReference(path: "src/a.swift", line: nil, column: nil)])
    }

    @Test func aFileNameAloneIsAPathOnlyWithALine() {
        #expect(paths("Package.swift:12") == [TerminalPathReference(path: "Package.swift", line: 12, column: nil)])
        #expect(paths("Package.swift is here").isEmpty)
    }

    @Test func punctuationAfterAPathIsNotPartOfIt() {
        #expect(paths("(src/foo.swift:42).").map(\.path) == ["src/foo.swift"])
        #expect(paths("error in src/foo.swift:42:7: boom") == [TerminalPathReference(path: "src/foo.swift", line: 42, column: 7)])
        #expect(paths("see src/foo.swift.").map(\.path) == ["src/foo.swift"])
        #expect(paths("'src/foo.swift'").map(\.path) == ["src/foo.swift"])
        #expect(paths("--config=/etc/app.conf").map(\.path) == ["/etc/app.conf"])
    }

    @Test func aUrlIsNotAlsoAPath() {
        let candidates = found("https://x.y/a/b.swift:3")
        #expect(candidates.count == 1)
        #expect(urls("https://x.y/a/b.swift:3").count == 1)
    }

    @Test func slashesAloneAreNotAPath() {
        #expect(paths("// - / ///").isEmpty)
        #expect(paths("-rw-r--r-- 1 kurt").isEmpty)
    }

    @Test func rangesCountUtf16UnitsNotCharacters() {
        let line = "😀 src/a.swift"
        let candidates = found(line)
        #expect(candidates.count == 1)
        #expect(text(candidates[0], in: line) == "src/a.swift")
    }

    // MARK: Resolving

    let home = URL(filePath: "/Users/kurt", directoryHint: .isDirectory)

    func resolve(_ path: String, in directory: String?) -> String? {
        TerminalPathReference(path: path, line: nil, column: nil)
            .resolved(against: directory.map { URL(filePath: $0, directoryHint: .isDirectory) }, home: home)?
            .path(percentEncoded: false)
    }

    @Test func anAbsolutePathNeedsNoDirectory() {
        #expect(resolve("/etc/hosts", in: nil) == "/etc/hosts")
    }

    @Test func aHomePathResolvesAgainstHome() {
        #expect(resolve("~/x/y", in: "/tmp") == "/Users/kurt/x/y")
    }

    @Test func aRelativePathResolvesAgainstTheDirectory() {
        #expect(resolve("src/a.swift", in: "/work/repo") == "/work/repo/src/a.swift")
        #expect(resolve("./a/b.ts", in: "/work/repo") == "/work/repo/a/b.ts")
        #expect(resolve("../x.md", in: "/work/repo") == "/work/x.md")
    }

    @Test func aRelativePathWithNoDirectoryDoesNotResolve() {
        #expect(resolve("src/a.swift", in: nil) == nil)
    }
}
