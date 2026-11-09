import Core
import Darwin
import Dispatch
import Foundation
import Synchronization

/// A process on the master side of a pseudo-terminal.
///
/// The descriptor's life is the one thing here that needs care. Reading, the
/// exit watcher and the caller's own writes all meet it, and a descriptor
/// closed under one of them can be a different file by the time it is used
/// again. So it is closed in exactly one place, the read source's cancel
/// handler, and everything else uses it under the same lock that handler takes.
///
/// Output is held to a limit by ``PTYOutputBuffer``, which pauses reading when
/// the consumer falls behind, so a process that writes without end is slowed
/// to the speed of whatever is drawing it instead of filling memory.
final class LivePTYSession: PTYSession {
    /// The master side, shared with the read source's handlers. A class
    /// because a `Mutex` cannot be copied into a closure, and so that the
    /// handlers need not hold the session, which holds the source.
    private final class Descriptor: Sendable {
        let master: Mutex<Int32?>

        init(_ master: Int32) { self.master = Mutex(master) }

        func close() {
            master.withLock {
                if let master = $0 { Darwin.close(master) }
                $0 = nil
            }
        }
    }

    private struct Exit {
        var status: Int32?
        var waiters: [CheckedContinuation<Int32, Never>] = []
    }

    let output: AsyncStream<Data>

    private let pid: pid_t
    private let descriptor: Descriptor
    private let exit = Mutex(Exit())

    private let source: any DispatchSourceRead
    let buffer: PTYOutputBuffer

    init(master: Int32, pid: pid_t) {
        self.pid = pid
        let descriptor = Descriptor(master)
        self.descriptor = descriptor

        // CONCURRENCY: kqueue readiness for a descriptor has no `async`
        // equivalent, and a blocking `read` on the cooperative pool would
        // starve it. The handler does one non-blocking read and hands it on.
        let source = DispatchSource.makeReadSource(
            fileDescriptor: master, queue: DispatchQueue(label: "herder.pty.read.\(pid)")
        )
        self.source = source

        let buffer = PTYOutputBuffer(
            pause: { [source] in source.suspend() },
            resume: { [source] in source.resume() }
        )
        self.buffer = buffer

        source.setEventHandler { [source] in
            var bytes = [UInt8](repeating: 0, count: 64 * 1024)
            let count = read(master, &bytes, bytes.count)
            if count > 0 {
                buffer.append(Data(bytes.prefix(count)))
            } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
                // EOF, or EIO, which is what a master reports once every
                // process holding the slave has gone.
                source.cancel()
            }
        }
        source.setCancelHandler {
            descriptor.close()
            buffer.finish()
        }
        source.resume()

        output = AsyncStream(
            unfolding: { await buffer.next() },
            onCancel: { [source] in Self.stop(source, buffer) }
        )

        // CONCURRENCY: `waitpid` blocks until the process ends, so it gets a
        // thread of its own rather than one of the cooperative pool's.
        let thread = Thread { [self] in reap() }
        thread.name = "herder.pty.reap.\(pid)"
        thread.start()
    }

    private func reap() {
        // Waits without reaping, then reaps under the lock `send` takes, so a
        // signal is never sent to a pid that has been reaped and reused.
        var info = siginfo_t()
        while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) < 0 && errno == EINTR {}
        let (status, waiters) = exit.withLock { state in
            var raw: Int32 = 0
            while waitpid(pid, &raw, 0) < 0 && errno == EINTR {}
            // The macros `WIFEXITED` and friends are not imported: this is
            // what they expand to.
            let signal = raw & 0x7f
            let status = signal == 0 ? (raw >> 8) & 0xff : 128 + signal
            state.status = status
            defer { state.waiters = [] }
            return (status, state.waiters)
        }
        for waiter in waiters { waiter.resume(returning: status) }
    }

    private var hasExited: Bool { exit.withLock { $0.status != nil } }

    func write(_ data: Data) async {
        var remaining = data[...]
        while !remaining.isEmpty, !Task.isCancelled {
            let written: Int? = descriptor.master.withLock { master in
                guard let master else { return nil }
                let count = remaining.withUnsafeBytes { Darwin.write(master, $0.baseAddress, $0.count) }
                if count >= 0 { return count }
                return errno == EAGAIN || errno == EINTR ? 0 : nil
            }
            guard let written else { return }
            if written == 0 {
                // The terminal's input buffer is full: the process is not
                // reading. Wait for it rather than spin.
                try? await Task.sleep(for: .milliseconds(5))
            } else {
                remaining = remaining.dropFirst(written)
            }
        }
    }

    func resize(_ size: PTYSize) async {
        var window = winsize(ws_row: size.rows, ws_col: size.columns, ws_xpixel: 0, ws_ypixel: 0)
        descriptor.master.withLock { master in
            guard let master else { return }
            _ = ioctl(master, TIOCSWINSZ, &window)
        }
    }

    func foregroundProcess() async -> PTYProcess? {
        guard !hasExited else { return nil }
        let group = descriptor.master.withLock { master in
            master.map { tcgetpgrp($0) }
        }
        guard let group, group > 0, let arguments = ProcessArguments.of(group), let first = arguments.first else {
            return nil
        }
        var name = URL(filePath: first).lastPathComponent
        if name.hasPrefix("-") { name.removeFirst() }
        let commandLine = ([name] + arguments.dropFirst()).joined(separator: " ")
        return PTYProcess(id: group, name: name, commandLine: commandLine, isShell: group == pid)
    }

    func workingDirectory() async -> URL? {
        hasExited ? nil : ProcessArguments.workingDirectory(of: pid)
    }

    func waitForExit() async -> Int32 {
        await withCheckedContinuation { continuation in
            let status = exit.withLock { state -> Int32? in
                if let status = state.status { return status }
                state.waiters.append(continuation)
                return nil
            }
            if let status { continuation.resume(returning: status) }
        }
    }

    /// How long a process is given to go before it is asked harder.
    static let grace: DispatchTimeInterval = .seconds(2)

    /// A hang-up is not always enough: opencode ignores SIGHUP and, once
    /// it is idle, does not notice its terminal going either, and was left
    /// running with no window. So a process still here after ``grace`` is
    /// sent SIGTERM, and SIGKILL after another.
    func terminate() {
        let wasRunning = send(SIGHUP)
        Self.stop(source, buffer)
        guard wasRunning else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.grace) { [self] in
            guard send(SIGTERM) else { return }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.grace) { [self] in
                send(SIGKILL)
            }
        }
    }

    func terminateNow() {
        send(SIGHUP)
        send(SIGTERM)
        Self.stop(source, buffer)
    }

    /// Signals the process's group, unless the process has been reaped.
    /// Whether it was sent.
    @discardableResult
    private func send(_ signal: Int32) -> Bool {
        exit.withLock { state in
            guard state.status == nil else { return false }
            killpg(pid, signal)
            return true
        }
    }

    /// Cancels reading. A source paused for backpressure is let go as well,
    /// because a suspended source never runs its cancel handler, and that is
    /// where the descriptor is closed and the output ended.
    private static func stop(_ source: any DispatchSourceRead, _ buffer: PTYOutputBuffer) {
        source.cancel()
        buffer.release()
    }

    deinit { Self.stop(source, buffer) }
}
