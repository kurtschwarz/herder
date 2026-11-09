import Core
import Foundation
import Testing

@testable import RepositoriesFeature

@Suite struct SessionHistoryDigestTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Noon on a Wednesday.
    let now = Date(timeIntervalSince1970: Double(1_700_000_000 - 1_700_000_000 % 86_400 + 12 * 3600))

    func ended(hoursAgo hours: Double) -> SessionHistoryRecord {
        SessionHistoryRecord(
            id: UUID(), agentID: "claude-code", agentName: "Claude Code",
            worktree: WorkspaceID(URL(filePath: "/code/api")), title: "t",
            startedAt: now.addingTimeInterval(-hours * 3600 - 60),
            endedAt: now.addingTimeInterval(-hours * 3600), endReason: .closed
        )
    }

    @Test func sessionsAreGroupedByTheDayTheyEnded() {
        let digest = SessionHistoryDigest(
            ended: [ended(hoursAgo: 1), ended(hoursAgo: 4), ended(hoursAgo: 14), ended(hoursAgo: 20)],
            now: now, calendar: calendar
        )

        #expect(digest.today.count == 2)
        #expect(digest.yesterday.count == 2)
    }

    @Test func nothingOlderThanYesterdayIsListedButAllAreCounted() {
        let digest = SessionHistoryDigest(
            ended: [ended(hoursAgo: 1), ended(hoursAgo: 60), ended(hoursAgo: 90)],
            now: now, calendar: calendar
        )

        #expect(digest.today.count == 1)
        #expect(digest.yesterday.isEmpty)
        #expect(digest.total == 3)
    }

    @Test func rowsStopAtTheLimit() {
        let many = (0..<9).map { ended(hoursAgo: Double($0) * 0.5) }
        let digest = SessionHistoryDigest(ended: many, now: now, calendar: calendar)

        #expect(digest.today.count + digest.yesterday.count == SessionHistoryDigest.rowLimit)
        #expect(digest.total == 9)
    }

    @Test func noHistoryIsEmpty() {
        #expect(SessionHistoryDigest(ended: [], now: now, calendar: calendar).isEmpty)
    }
}
