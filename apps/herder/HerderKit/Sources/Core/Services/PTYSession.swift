import Foundation

/// One process running in a pseudo-terminal, and the way to talk to it.
public protocol PTYSession: AnyObject, Sendable {
    /// What the process wrote, as it arrives. Ends when the terminal closes,
    /// which is after the process has gone and everything it wrote was read.
    /// One consumer: a second `for await` would split the bytes between them.
    ///
    /// Bounded: what is not yet taken is held to a limit, and past it the
    /// process is made to wait for its reader. A consumer that reads slowly
    /// slows the process; one that stops reading stops it.
    var output: AsyncStream<Data> { get }

    /// Sends bytes to the process as if typed. Waits while the terminal's input
    /// buffer is full, and returns early if the task is cancelled.
    func write(_ data: Data) async

    func resize(_ size: PTYSize) async

    /// What the terminal is running at the front right now, or `nil` once it
    /// is gone.
    func foregroundProcess() async -> PTYProcess?

    /// The directory the started process is in, or `nil` once it is gone. The
    /// shell's, not whatever it launched: that is where a new command lands.
    func workingDirectory() async -> URL?

    /// Waits for the started process to exit and returns how: its exit code,
    /// or 128 plus the signal that ended it.
    func waitForExit() async -> Int32

    /// Hangs up on the terminal. Does not wait for the process to go: await
    /// ``waitForExit()`` for that.
    func terminate()
}
