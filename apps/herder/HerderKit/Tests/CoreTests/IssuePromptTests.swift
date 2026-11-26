import Foundation
import Testing

@testable import Core

@Suite struct IssuePromptTests {
    func detail(body: String = "Make it faster.", comments: [GitHubIssueDetail.Comment] = []) -> GitHubIssueDetail {
        GitHubIssueDetail(
            issue: GitHubIssue(number: 12, url: URL(string: "https://github.com/o/r/issues/12")!, title: "Slow start"),
            body: body,
            comments: comments
        )
    }

    @Test func theNumberAndTitleComeFirstThenTheLinkThenTheBody() {
        #expect(IssuePrompt.text(for: detail()) == """
            #12 Slow start

            https://github.com/o/r/issues/12

            Make it faster.
            """)
    }

    @Test func commentsFollowWithTheirAuthorsOldestFirst() {
        let text = IssuePrompt.text(for: detail(comments: [
            .init(author: "ada", body: "Seen on 3.1."),
            .init(author: nil, body: "Me too."),
        ]))

        #expect(text.hasSuffix("""
            Comments, oldest first:

            @ada:
            Seen on 3.1.

            ghost:
            Me too.
            """))
    }

    @Test func anEmptyBodyAndBlankCommentsLeaveNothingBehind() {
        let text = IssuePrompt.text(for: detail(body: "  \n", comments: [.init(author: "ada", body: " ")]))

        #expect(text == "#12 Slow start\n\nhttps://github.com/o/r/issues/12")
    }

    @Test func onlyTheMostRecentFiftyCommentsGoIn() {
        let comments = (1...60).map { GitHubIssueDetail.Comment(author: "a", body: "comment \($0)") }

        let text = IssuePrompt.text(for: detail(comments: comments))

        #expect(!text.contains("comment 10\n"))
        #expect(text.contains("comment 11\n"))
        #expect(text.hasSuffix("comment 60"))
        #expect(text.components(separatedBy: "@a:").count - 1 == 50)
    }
}
