import Foundation
import Synchronization
import Testing

@testable import Services

/// The limit on what a terminal holds, without a process: what pauses the
/// producer, what resumes it, and that the two always balance.
@Suite struct PTYOutputBufferTests {
    /// Counts what the buffer asks of its producer.
    final class Producer: Sendable {
        private let counts = Mutex((pauses: 0, resumes: 0))

        var pauses: Int { counts.withLock { $0.pauses } }
        var resumes: Int { counts.withLock { $0.resumes } }

        func pause() { counts.withLock { $0.pauses += 1 } }
        func resume() { counts.withLock { $0.resumes += 1 } }
    }

    let producer = Producer()

    func buffer(highWater: Int = 100, lowWater: Int = 40, maxTake: Int = 1000) -> PTYOutputBuffer {
        PTYOutputBuffer(
            highWater: highWater, lowWater: lowWater, maxTake: maxTake,
            pause: { [producer] in producer.pause() },
            resume: { [producer] in producer.resume() }
        )
    }

    func bytes(_ count: Int, _ value: UInt8 = 0x79) -> Data {
        Data(repeating: value, count: count)
    }

    @Test func belowTheLimitNothingIsPaused() {
        let buffer = buffer()
        buffer.append(bytes(99))
        #expect(!buffer.isPaused)
        #expect(producer.pauses == 0)
    }

    @Test func reachingTheLimitPausesTheProducerOnce() {
        let buffer = buffer()
        buffer.append(bytes(60))
        buffer.append(bytes(60))
        buffer.append(bytes(60))
        #expect(buffer.isPaused)
        #expect(producer.pauses == 1)
    }

    @Test func takingEverythingResumesIt() async {
        let buffer = buffer()
        buffer.append(bytes(150))
        let taken = await buffer.next()
        #expect(taken?.count == 150)
        #expect(!buffer.isPaused)
        #expect(producer.resumes == 1)
    }

    @Test func itStaysPausedUntilUnderTheLowWaterMark() async {
        let buffer = buffer(maxTake: 50)
        for _ in 0..<4 { buffer.append(bytes(50)) }
        #expect(buffer.isPaused)

        _ = await buffer.next()
        #expect(buffer.bufferedBytes == 150)
        #expect(buffer.isPaused)
        _ = await buffer.next()
        _ = await buffer.next()
        #expect(buffer.bufferedBytes == 50)
        #expect(buffer.isPaused)
        _ = await buffer.next()
        #expect(!buffer.isPaused)
        #expect(producer.resumes == 1)
    }

    @Test func piecesAreHandedOutTogetherUpToTheLimitAndInOrder() async {
        let buffer = buffer(highWater: 10_000, lowWater: 10, maxTake: 5)
        buffer.append(bytes(2, 0x61))
        buffer.append(bytes(2, 0x62))
        buffer.append(bytes(2, 0x63))
        #expect(await buffer.next() == Data("aabb".utf8))
        #expect(await buffer.next() == Data("cc".utf8))
    }

    @Test func aPieceBiggerThanTheLimitIsNotSplitOrStuck() async {
        let buffer = buffer(highWater: 10_000, lowWater: 10, maxTake: 5)
        buffer.append(bytes(8))
        #expect(await buffer.next()?.count == 8)
    }

    @Test func aWaitingReaderGetsTheNextPieceStraightAway() async {
        let buffer = buffer()
        async let next = buffer.next()
        try? await Task.sleep(for: .milliseconds(20))
        buffer.append(bytes(10))
        #expect(await next?.count == 10)
        #expect(buffer.bufferedBytes == 0)
    }

    @Test func whatIsLeftIsHandedOutAfterTheEndAndThenNothing() async {
        let buffer = buffer()
        buffer.append(bytes(10))
        buffer.finish()
        #expect(await buffer.next()?.count == 10)
        #expect(await buffer.next() == nil)
    }

    @Test func theEndWakesAWaitingReader() async {
        let buffer = buffer()
        async let next = buffer.next()
        try? await Task.sleep(for: .milliseconds(20))
        buffer.finish()
        #expect(await next == nil)
    }

    @Test func cancellingAWaitingReaderEndsItsWait() async {
        let buffer = buffer()
        let reader = Task { await buffer.next() }
        try? await Task.sleep(for: .milliseconds(20))
        reader.cancel()
        #expect(await reader.value == nil)
    }

    @Test func releasingResumesOnlyWhatWasPaused() {
        let buffer = buffer()
        buffer.release()
        #expect(producer.resumes == 0)

        buffer.append(bytes(200))
        buffer.release()
        buffer.release()
        #expect(producer.pauses == 1)
        #expect(producer.resumes == 1)
    }

    @Test func pausesAndResumesBalanceUnderARace() async {
        let buffer = buffer(highWater: 4096, lowWater: 1024, maxTake: 2048)
        let total = 512 * 4_000
        async let produced: Void = Task.detached {
            var sent = 0
            while sent < total {
                buffer.append(Data(repeating: 0x79, count: 512))
                sent += 512
            }
            buffer.finish()
        }.value
        var received = 0
        while let chunk = await buffer.next() { received += chunk.count }
        await produced
        #expect(received == total)
        #expect(producer.pauses == producer.resumes)
    }
}
