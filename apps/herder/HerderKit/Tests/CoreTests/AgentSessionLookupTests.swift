import Foundation
import Testing

@testable import Core

@Suite struct AgentSessionLookupTests {
    let here = PathKey(canonical: "/code/api")
    let started = Date(timeIntervalSince1970: 1_000_000)

    @Test func readsOpencodesJSON() {
        let output = """
        [
          {"id": "ses_new", "title": "Fix", "created": 1794020356270, "directory": "/code/api"},
          {"id": "ses_old", "title": "Old", "created": 1794009845, "directory": "/code/api"}
        ]
        """

        let candidates = AgentSessionLookup.candidates(in: output)

        #expect(candidates.map(\.id) == ["ses_new", "ses_old"])
        // Milliseconds, as opencode writes them, and seconds, as others might.
        #expect(candidates.first?.created == Date(timeIntervalSince1970: 1_794_020_356.270))
        #expect(candidates.last?.created == Date(timeIntervalSince1970: 1_794_009_845))
        #expect(candidates.first?.directory == PathKey(canonical: "/code/api"))
    }

    @Test func readsAnIdALine() {
        let output = "ses_a\tFirst\t11/7/2026\nses_b\tSecond\n\n"

        #expect(AgentSessionLookup.candidates(in: output).map(\.id) == ["ses_a", "ses_b"])
    }

    @Test func matchesTheEarliestSessionMadeHereAfterTheTabStarted() {
        let candidates = [
            AgentSessionLookup.Candidate(id: "later", directory: here, created: started.addingTimeInterval(60)),
            AgentSessionLookup.Candidate(id: "mine", directory: here, created: started.addingTimeInterval(2)),
            AgentSessionLookup.Candidate(id: "before", directory: here, created: started.addingTimeInterval(-600)),
            AgentSessionLookup.Candidate(
                id: "elsewhere", directory: PathKey(canonical: "/code/web"), created: started.addingTimeInterval(1)
            ),
        ]

        #expect(AgentSessionLookup.match(candidates, directory: here, started: started, claimed: []) == "mine")
        #expect(AgentSessionLookup.match(candidates, directory: here, started: started, claimed: ["mine"]) == "later")
    }

    @Test func withNoTimesTheNewestUnclaimedIsTaken() {
        let candidates = [AgentSessionLookup.Candidate(id: "a"), AgentSessionLookup.Candidate(id: "b")]

        #expect(AgentSessionLookup.match(candidates, directory: here, started: started, claimed: ["a"]) == "b")
    }

    @Test func nothingFitsIsNil() {
        let candidates = [AgentSessionLookup.Candidate(id: "old", created: started.addingTimeInterval(-600))]

        #expect(AgentSessionLookup.match(candidates, directory: here, started: started, claimed: []) == nil)
    }

    @Test func onlyAnIdAShellCannotReadAsMoreIsSafe() {
        #expect(AgentSessionLookup.isSafe("ses_e4cccbfa3ffeECBTVKno9Jd7mK"))
        #expect(AgentSessionLookup.isSafe("6f9619ff-8b86-d011"))
        #expect(!AgentSessionLookup.isSafe("ses; rm -rf ~"))
        #expect(!AgentSessionLookup.isSafe("$(whoami)"))
        #expect(!AgentSessionLookup.isSafe(""))
    }
}
