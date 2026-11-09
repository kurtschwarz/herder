import Core
import Foundation

/// The part of a repository's history the sidebar has room for: the sessions
/// that ended today and yesterday, up to a few rows between them, and how
/// many there are in all.
struct SessionHistoryDigest: Equatable {
    /// How many rows the sidebar lists before "All history".
    static let rowLimit = 5

    var today: [AgentSession] = []
    var yesterday: [AgentSession] = []

    /// Every ended session in the repository, however long ago.
    var total = 0

    var isEmpty: Bool { total == 0 }

    /// `ended` is latest end first, as ``SessionHistory/ended(in:)`` gives it.
    init(ended: [AgentSession], now: Date = .now, calendar: Calendar = .current) {
        total = ended.count
        var room = Self.rowLimit
        for record in ended {
            guard room > 0, let endedAt = record.endedAt else { break }
            if calendar.isDate(endedAt, inSameDayAs: now) {
                today.append(record)
            } else if let day = calendar.date(byAdding: .day, value: -1, to: now),
                      calendar.isDate(endedAt, inSameDayAs: day) {
                yesterday.append(record)
            } else if endedAt < now {
                // Sorted latest first, so everything after is older still.
                break
            } else {
                // Ended in the future by this clock: the clock moved. Today.
                today.append(record)
            }
            room -= 1
        }
    }
}
