import Testing

@testable import Core

@Suite struct IssueReferenceTests {
    @Test func aHashAndANumberNameAnIssueOfTheRepositoryBeingListed() {
        #expect(IssueReference(parsing: "#123") == IssueReference(number: 123))
        #expect(IssueReference(parsing: "  #7 \n") == IssueReference(number: 7))
    }

    @Test func aLinkNamesTheIssueAndItsRepository() {
        #expect(IssueReference(parsing: "https://github.com/kurtschwarz/herder/issues/144")
            == IssueReference(number: 144, repository: "kurtschwarz/herder"))
        #expect(IssueReference(parsing: "https://github.com/o/r/issues/5#issuecomment-1")
            == IssueReference(number: 5, repository: "o/r"))
    }

    @Test(arguments: [
        "", "123", "#", "#0", "#abc", "fix the crash", "#12 extra",
        "https://github.com/o/r/pull/5", "https://github.com/o/r", "https://gitlab.com/o/r/issues/5",
        "https://github.com/o/r/issues/x",
    ])
    func anythingElseIsASearch(text: String) {
        #expect(IssueReference(parsing: text) == nil)
    }
}
