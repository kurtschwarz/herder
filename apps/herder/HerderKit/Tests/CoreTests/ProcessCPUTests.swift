import Foundation
import Testing

@testable import Core

/// CPU as a rate: from two samples, and only for a process both of them saw.
@Suite struct ProcessCPUTests {
    typealias F = ProcessFixtures

    @Test func aProcessSeenOnceHasNoRate() {
        let only = F.sample(F.process(200, cpu: 5))

        #expect(ProcessCPU.percentages(from: nil, to: only).isEmpty)
    }

    @Test func aRateIsTheCPUTimeUsedOverTheTimeThatPassed() throws {
        let first = F.sample(at: 0, F.process(200, cpu: 5))
        let second = F.sample(at: 2, F.process(200, cpu: 6))

        let rates = ProcessCPU.percentages(from: first, to: second)

        // One second of CPU in two is half a core.
        #expect(try #require(rates[F.process(200).key]) == 50)
    }

    @Test func aBusyProcessCanUseMoreThanOneCore() throws {
        let first = F.sample(at: 0, F.process(200, cpu: 0))
        let second = F.sample(at: 2, F.process(200, cpu: 6))

        #expect(try #require(ProcessCPU.percentages(from: first, to: second)[F.process(200).key]) == 300)
    }

    @Test func aProcessStartedBetweenSamplesHasNoRateYet() {
        let first = F.sample(at: 0, F.process(200))
        let second = F.sample(at: 2, F.process(200), F.process(201, cpu: 1))

        let rates = ProcessCPU.percentages(from: first, to: second)

        #expect(rates[F.process(201).key] == nil)
        #expect(rates[F.process(200).key] != nil)
    }

    @Test func aReusedPidIsNotTheProcessThatHadItBefore() {
        // The same pid, started later: a different process.
        let first = F.sample(at: 0, F.process(200, cpu: 50, started: 1))
        let second = F.sample(at: 2, F.process(200, cpu: 1, started: 2))

        #expect(ProcessCPU.percentages(from: first, to: second)[F.process(200, started: 2).key] == nil)
    }

    @Test func noTimePassingGivesNoRates() {
        let first = F.sample(at: 5, F.process(200, cpu: 1))
        let second = F.sample(at: 5, F.process(200, cpu: 2))

        #expect(ProcessCPU.percentages(from: first, to: second).isEmpty)
    }
}
