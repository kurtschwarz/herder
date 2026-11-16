import Foundation

/// How the Task Manager writes its numbers.
enum TaskFormat {
    /// What there is no number for yet.
    static let none = "\u{2014}"

    /// A share of one core, as Activity Monitor writes it: `12.3%`.
    static func cpu(_ percent: Double?) -> String {
        guard let percent else { return none }
        return String(format: "%.1f%%", percent)
    }

    /// A share of the whole machine, from 0 to 1, in whole percent.
    static func share(_ share: Double?) -> String {
        guard let share else { return none }
        return "\(Int((share * 100).rounded()))%"
    }

    static func bytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }

    /// How long it has been running, to the two largest units that matter:
    /// `42s`, `5m 12s`, `2h 14m`, `3d 4h`.
    static func uptime(from start: Date?, to now: Date?) -> String {
        guard let start, let now else { return none }
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        switch seconds {
        case ..<60: return "\(seconds)s"
        case ..<3600: return "\(seconds / 60)m \(seconds % 60)s"
        case ..<86_400: return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
        default: return "\(seconds / 86_400)d \(seconds % 86_400 / 3600)h"
        }
    }

    static func processes(_ count: Int) -> String {
        "\(count) \(count == 1 ? "process" : "processes")"
    }
}
