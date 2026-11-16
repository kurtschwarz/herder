import Core
import Foundation
import Testing

@testable import RepositoriesFeature

@Suite struct SessionHistoryDigestTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    /// Noon on Wednesday 15 November 2023.
    var now: Date { date(2023, 11, 15) }

    func ended(hoursAgo hours: Double) -> AgentSession {
        ended(at: now.addingTimeInterval(-hours * 3600))
    }

    func ended(daysAgo days: Int) -> AgentSession {
        ended(at: calendar.date(byAdding: .day, value: -days, to: now)!)
    }

    func ended(at date: Date) -> AgentSession {
        AgentSession(
            id: UUID(), agentID: "claude-code", agentName: "Claude Code",
            worktree: WorkspaceID(URL(filePath: "/code/api")), title: "t",
            startedAt: date.addingTimeInterval(-60),
            endedAt: date, endReason: .closed
        )
    }

    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func digest(_ ended: [AgentSession], expanded: Bool = false) -> SessionHistoryDigest {
        SessionHistoryDigest(ended: ended, isExpanded: expanded, now: now, calendar: calendar)
    }

    func titles(_ digest: SessionHistoryDigest) -> [String] { digest.groups.map(\.title) }

    @Test func sessionsAreGroupedByTheDayTheyEnded() {
        let digest = digest([ended(hoursAgo: 1), ended(hoursAgo: 4), ended(hoursAgo: 14), ended(hoursAgo: 20)])

        #expect(titles(digest) == ["Today", "Yesterday"])
        #expect(digest.groups.map(\.sessions.count) == [2, 2])
    }

    @Test func nothingOlderThanYesterdayIsListedButAllAreCounted() {
        let digest = digest([ended(hoursAgo: 1), ended(hoursAgo: 60), ended(hoursAgo: 90)])

        #expect(titles(digest) == ["Today"])
        #expect(digest.total == 3)
    }

    @Test func rowsStopAtTheLimit() {
        let many = (0..<9).map { ended(hoursAgo: Double($0) * 0.5) }
        let digest = digest(many)

        #expect(digest.groups.flatMap(\.sessions).count == SessionHistoryDigest.rowLimit)
        #expect(digest.total == 9)
    }

    @Test func noHistoryIsEmpty() {
        #expect(digest([]).isEmpty)
    }

    @Test func expandedHasNoRowLimit() {
        let many = (0..<20).map { ended(hoursAgo: Double($0) * 0.1) }
        let digest = digest(many, expanded: true)

        #expect(digest.groups.flatMap(\.sessions).count == 20)
    }

    @Test func expandedGroupsBreakAtEachBoundary() {
        // Today is Wed 15 Nov: midnight is 12 hours ago.
        let digest = digest([
            ended(hoursAgo: 11),       // today
            ended(hoursAgo: 13),       // yesterday
            ended(hoursAgo: 12 + 24),  // yesterday's midnight: still yesterday
            ended(hoursAgo: 37),       // the day before: previous 7 days
            ended(daysAgo: 7),         // 8 Nov 12:00, after 8 Nov 00:00
            ended(at: date(2023, 11, 7, hour: 23)), // before the 7 day line
            ended(at: date(2023, 10, 16, hour: 0)), // 30 days back is 16 Oct 00:00
            ended(at: date(2023, 10, 15, hour: 23)), // just before it
            ended(at: date(2023, 9, 3)),
        ], expanded: true)

        #expect(titles(digest) == [
            "Today", "Yesterday", "Previous 7 days", "Previous 30 days", "October", "September",
        ])
        #expect(digest.groups.map(\.sessions.count) == [1, 2, 2, 2, 1, 1])
    }

    @Test func monthsInEarlierYearsNameTheYear() {
        let digest = digest([
            ended(at: date(2023, 8, 20)),
            ended(at: date(2022, 12, 31)),
            ended(at: date(2022, 12, 1)),
            ended(at: date(2022, 10, 5)),
        ], expanded: true)

        #expect(titles(digest) == ["August", "December 2022", "October 2022"])
        #expect(digest.groups.map(\.sessions.count) == [1, 2, 1])
    }

    @Test func aSessionEndingInTheFutureCountsAsToday() {
        let future = ended(hoursAgo: -30)

        #expect(titles(digest([future, ended(hoursAgo: 1)])) == ["Today"])
        #expect(digest([future, ended(hoursAgo: 1)]).groups[0].sessions.count == 2)
        #expect(titles(digest([future, ended(daysAgo: 3)], expanded: true)) == ["Today", "Previous 7 days"])
    }
}
