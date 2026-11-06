import Foundation
import Synchronization

/// What a terminal's process has written and its reader has not yet taken,
/// held to a limit.
///
/// The limit is what makes a runaway `yes` cost a megabyte rather than all the
/// memory there is. Past `highWater` the buffer pauses its producer, the read
/// source; nothing then reads the pseudo-terminal, the kernel's own buffer for
/// it fills, and the process blocks in `write` until there is room. Its reader
/// taking enough to bring the buffer under `lowWater` resumes it.
///
/// Pulled rather than pushed, which is the point: a push into an unbounded
/// stream has no way to hear that its consumer has fallen behind.
///
/// `pause` and `resume` are called under the lock that guards the count. A
/// dispatch source crashes on a resume it was not suspended for, and the
/// producer and the consumer run on different threads; deciding and acting in
/// one critical section is what keeps the two calls balanced.
final class PTYOutputBuffer: Sendable {
    private struct State {
        var chunks: [Data] = []
        var bytes = 0
        var isPaused = false
        var isFinished = false
        var waiter: CheckedContinuation<Data?, Never>?
    }

    /// Buffered bytes past which the producer is paused.
    let highWater: Int

    /// Buffered bytes at or under which a paused producer is resumed.
    let lowWater: Int

    /// The most handed to the reader at once, so one turn of its loop is
    /// bounded too.
    let maxTake: Int

    private let state = Mutex(State())
    private let pause: @Sendable () -> Void
    private let resume: @Sendable () -> Void

    init(
        highWater: Int = 1 << 20,
        lowWater: Int = 256 << 10,
        maxTake: Int = 256 << 10,
        pause: @escaping @Sendable () -> Void,
        resume: @escaping @Sendable () -> Void
    ) {
        precondition(lowWater < highWater)
        self.highWater = highWater
        self.lowWater = lowWater
        self.maxTake = maxTake
        self.pause = pause
        self.resume = resume
    }

    /// How much is waiting to be taken.
    var bufferedBytes: Int { state.withLock { $0.bytes } }

    /// Whether the producer is paused.
    var isPaused: Bool { state.withLock { $0.isPaused } }

    /// What the producer read. Called from the read source's queue.
    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        let waiter = state.withLock { state -> CheckedContinuation<Data?, Never>? in
            guard !state.isFinished else { return nil }
            // A reader already waiting takes it straight away: nothing is
            // buffered, so there is nothing to pause for.
            if let waiter = state.waiter {
                state.waiter = nil
                return waiter
            }
            state.chunks.append(data)
            state.bytes += data.count
            if state.bytes >= highWater, !state.isPaused {
                state.isPaused = true
                pause()
            }
            return nil
        }
        waiter?.resume(returning: data)
    }

    /// The producer has nothing more. What is buffered is still handed out;
    /// after it, ``next()`` returns `nil`.
    func finish() {
        let waiter = state.withLock { state -> CheckedContinuation<Data?, Never>? in
            state.isFinished = true
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume(returning: nil)
    }

    /// Lets a paused producer go, for a source being cancelled: a suspended
    /// dispatch source does not run its cancel handler until it is resumed.
    func release() {
        state.withLock { state in
            guard state.isPaused else { return }
            state.isPaused = false
            resume()
        }
    }

    /// The next of what the process wrote: everything buffered, up to
    /// ``maxTake``, as one piece. Waits when there is nothing yet, and returns
    /// `nil` once the producer has finished and everything was taken, or when
    /// the task is cancelled.
    func next() async -> Data? {
        if let ready = take() { return ready }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let immediate: (Data?)? = state.withLock { state in
                    if !state.chunks.isEmpty { return .some(takeLocked(&state)) }
                    if state.isFinished || Task.isCancelled { return .some(nil) }
                    state.waiter = continuation
                    return nil
                }
                if let immediate { continuation.resume(returning: immediate) }
            }
        } onCancel: {
            let waiter = state.withLock { state -> CheckedContinuation<Data?, Never>? in
                defer { state.waiter = nil }
                return state.waiter
            }
            waiter?.resume(returning: nil)
        }
    }

    private func take() -> Data?? {
        state.withLock { state in
            if !state.chunks.isEmpty { return .some(takeLocked(&state)) }
            return state.isFinished ? .some(nil) : nil
        }
    }

    private func takeLocked(_ state: inout State) -> Data? {
        var taken = Data()
        while let first = state.chunks.first, taken.isEmpty || taken.count + first.count <= maxTake {
            taken.append(first)
            state.chunks.removeFirst()
        }
        state.bytes -= taken.count
        if state.isPaused, state.bytes <= lowWater {
            state.isPaused = false
            resume()
        }
        return taken
    }
}
