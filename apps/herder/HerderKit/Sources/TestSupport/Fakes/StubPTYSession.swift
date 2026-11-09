#if DEBUG
import Core
import Foundation
import Synchronization

/// A terminal a test plays both ends of.
public final class StubPTYSession: PTYSession {
    private struct State {
        var written: [Data] = []
        var size: PTYSize
        var foreground: PTYProcess?
        var workingDirectory: URL?
        var status: Int32?
        var waiters: [CheckedContinuation<Int32, Never>] = []
        var terminated = false
    }

    public let output: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let state: Mutex<State>

    public let spec: PTYSpec

    public init(spec: PTYSpec) {
        self.spec = spec
        (output, continuation) = AsyncStream<Data>.makeStream()
        state = Mutex(State(
            size: spec.size,
            foreground: PTYProcess(
                id: 1, name: spec.executable.split(separator: "/").last.map(String.init) ?? spec.executable,
                commandLine: spec.executable, isShell: true
            ),
            workingDirectory: spec.workingDirectory
        ))
    }

    // MARK: PTYSession

    public func write(_ data: Data) async {
        state.withLock { $0.written.append(data) }
    }

    public func resize(_ size: PTYSize) async {
        state.withLock { $0.size = size }
    }

    public func foregroundProcess() async -> PTYProcess? {
        state.withLock { $0.status == nil ? $0.foreground : nil }
    }

    public func workingDirectory() async -> URL? {
        state.withLock { $0.status == nil ? $0.workingDirectory : nil }
    }

    public func waitForExit() async -> Int32 {
        await withCheckedContinuation { continuation in
            let status = state.withLock { state -> Int32? in
                if let status = state.status { return status }
                state.waiters.append(continuation)
                return nil
            }
            if let status { continuation.resume(returning: status) }
        }
    }

    public func terminate() {
        state.withLock { $0.terminated = true }
        exit(with: 129)
    }

    public func terminateNow() {
        terminate()
    }

    // MARK: What a test does and sees

    /// Everything written to the process, in order, as one string.
    public var input: String {
        state.withLock { String(decoding: $0.written.reduce(into: Data(), +=), as: UTF8.self) }
    }

    public var size: PTYSize { state.withLock { $0.size } }
    public var wasTerminated: Bool { state.withLock { $0.terminated } }

    /// The process writes `text`.
    public func emit(_ text: String) {
        continuation.yield(Data(text.utf8))
    }

    /// Something else is in the foreground: the user ran `commandLine`.
    public func run(_ commandLine: String) {
        let name = commandLine.split(separator: " ").first.map(String.init) ?? commandLine
        state.withLock { $0.foreground = PTYProcess(id: 2, name: name, commandLine: commandLine, isShell: false) }
    }

    /// The command finished and the shell is back in front.
    public func returnToShell() {
        state.withLock { state in
            state.foreground = PTYProcess(
                id: 1, name: "zsh", commandLine: "zsh", isShell: true
            )
        }
    }

    public func changeDirectory(to url: URL) {
        state.withLock { $0.workingDirectory = url }
    }

    /// The process ends with `status`, and the output with it.
    public func exit(with status: Int32) {
        let waiters = state.withLock { state -> [CheckedContinuation<Int32, Never>] in
            guard state.status == nil else { return [] }
            state.status = status
            defer { state.waiters = [] }
            return state.waiters
        }
        continuation.finish()
        for waiter in waiters { waiter.resume(returning: status) }
    }
}
#endif
