import Foundation
import Testing

@testable import Core

@Suite struct RelativeAgeTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func age(_ seconds: TimeInterval) -> String {
        RelativeAge.short(from: now.addingTimeInterval(-seconds), now: now)
    }

    @Test func underAMinuteIsNow() {
        #expect(age(0) == "now")
        #expect(age(59) == "now")
    }

    @Test func roundsDownToTheLargestUnit() {
        #expect(age(60) == "1m")
        #expect(age(14 * 60 + 59) == "14m")
        #expect(age(3600) == "1h")
        #expect(age(3 * 3600 + 3599) == "3h")
        #expect(age(86_400) == "1d")
        #expect(age(5 * 86_400) == "5d")
    }

    @Test func aFutureDateIsNow() {
        #expect(age(-500) == "now")
    }
}
