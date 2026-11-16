import Foundation

/// How long ago, in the shortest form that still reads: `now`, `14m`, `3h`,
/// `2d`. Rounds down, and never claims a future moment is in the past.
public enum RelativeAge {
    public static func short(from date: Date, now: Date = .now) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86_400)d"
        }
    }
}
