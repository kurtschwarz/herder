import Foundation

/// What one tile's sparkline draws: a value per refresh, for the last minute.
public struct MetricHistory: Sendable, Equatable {
    public struct Point: Sendable, Equatable {
        public var at: Date
        public var value: Double

        public init(at: Date, value: Double) {
            self.at = at
            self.value = value
        }
    }

    public static let window: TimeInterval = 60

    public private(set) var points: [Point] = []

    public init() {}

    /// Adds a value and lets go of any older than ``window`` before it.
    public mutating func append(_ value: Double, at date: Date) {
        points.append(Point(at: date, value: value))
        points.removeAll { date.timeIntervalSince($0.at) > Self.window }
    }
}
