import Core
import Foundation

/// What one tile's sparkline draws: a value per refresh, for the last minute.
struct MetricHistory: Sendable, Equatable {
    struct Point: Sendable, Equatable {
        var at: Date
        var value: Double

        init(at: Date, value: Double) {
            self.at = at
            self.value = value
        }
    }

    static let window: TimeInterval = 60

    private(set) var points: [Point] = []

    init() {}

    /// Adds a value and lets go of any older than ``window`` before it.
    mutating func append(_ value: Double, at date: Date) {
        points.append(Point(at: date, value: value))
        points.removeAll { date.timeIntervalSince($0.at) > Self.window }
    }
}
