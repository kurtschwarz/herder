import Core
import Foundation

/// The part of a repository's history the sidebar shows: by default the
/// sessions that ended today and yesterday, up to a few rows between them, or
/// with `isExpanded` every one, grouped by how long ago it ended. Also how many
/// there are in all.
struct SessionHistoryDigest: Equatable {
    /// How many rows the sidebar lists before "All history".
    static let rowLimit = 5

    /// Sessions that ended in the same stretch of time, latest end first.
    struct Group: Equatable {
        var title: String
        var sessions: [AgentSession]
    }

    /// Latest group first.
    var groups: [Group] = []

    /// Every ended session in the repository, however long ago.
    var total = 0

    var isEmpty: Bool { total == 0 }

    /// `ended` is latest end first, as ``SessionHistory/ended(in:)`` gives it.
    init(
        ended: [AgentSession],
        isExpanded: Bool = false,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        total = ended.count

        let startOfToday = calendar.startOfDay(for: now)
        func start(daysBack days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: startOfToday) ?? startOfToday
        }
        let yesterday = start(daysBack: 1)
        let week = start(daysBack: 7)
        let month = start(daysBack: 30)

        let monthName = DateFormatter()
        monthName.calendar = calendar
        monthName.timeZone = calendar.timeZone
        monthName.locale = calendar.locale ?? .current
        let thisYear = calendar.component(.year, from: now)

        var room = Self.rowLimit
        var key: String?
        for record in ended {
            guard isExpanded || room > 0, let endedAt = record.endedAt else { break }

            // Ending in the future by this clock means the clock moved: today.
            let bucket: String
            let title: String
            if endedAt >= startOfToday {
                (bucket, title) = ("today", "Today")
            } else if endedAt >= yesterday {
                (bucket, title) = ("yesterday", "Yesterday")
            } else if !isExpanded {
                // Sorted latest first, so everything after is older still.
                break
            } else if endedAt >= week {
                (bucket, title) = ("week", "Previous 7 days")
            } else if endedAt >= month {
                (bucket, title) = ("month", "Previous 30 days")
            } else {
                let year = calendar.component(.year, from: endedAt)
                monthName.setLocalizedDateFormatFromTemplate(year == thisYear ? "MMMM" : "MMMM yyyy")
                (bucket, title) = ("\(year)-\(calendar.component(.month, from: endedAt))", monthName.string(from: endedAt))
            }

            if key == bucket {
                groups[groups.count - 1].sessions.append(record)
            } else {
                groups.append(Group(title: title, sessions: [record]))
                key = bucket
            }
            room -= 1
        }
    }
}
