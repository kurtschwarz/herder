import Foundation
import Testing

@testable import TaskManagerFeature

@Suite struct TaskFormatTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func cpuIsADashUntilThereIsARate() {
        #expect(TaskFormat.cpu(nil) == "\u{2014}")
        #expect(TaskFormat.cpu(12.34) == "12.3%")
        #expect(TaskFormat.cpu(250) == "250.0%")
    }

    @Test func aShareIsInWholePercent() {
        #expect(TaskFormat.share(nil) == "\u{2014}")
        #expect(TaskFormat.share(0.234) == "23%")
    }

    @Test func uptimeShowsTheTwoLargestUnits() {
        #expect(TaskFormat.uptime(from: now.addingTimeInterval(-42), to: now) == "42s")
        #expect(TaskFormat.uptime(from: now.addingTimeInterval(-312), to: now) == "5m 12s")
        #expect(TaskFormat.uptime(from: now.addingTimeInterval(-(2 * 3600 + 14 * 60 + 9)), to: now) == "2h 14m")
        #expect(TaskFormat.uptime(from: now.addingTimeInterval(-(3 * 86_400 + 4 * 3600)), to: now) == "3d 4h")
    }

    @Test func aProcessWithNoStartHasNoUptime() {
        #expect(TaskFormat.uptime(from: nil, to: now) == "\u{2014}")
    }

    @Test func aStartInTheFutureIsZero() {
        #expect(TaskFormat.uptime(from: now.addingTimeInterval(5), to: now) == "0s")
    }

    @Test func processesAgreeWithTheirCount() {
        #expect(TaskFormat.processes(1) == "1 process")
        #expect(TaskFormat.processes(4) == "4 processes")
    }
}
