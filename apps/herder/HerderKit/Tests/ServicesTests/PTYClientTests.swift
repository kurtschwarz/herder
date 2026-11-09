import Core
import Foundation
@testable import Services
import Testing

/// Against real processes, because what is worth testing is the terminal
/// plumbing itself: the controlling terminal, the window size, the exit status,
/// and what the kernel says is in the foreground. A fake would only test itself.
@Suite(.timeLimit(.minutes(1))) struct LivePTYClientTests {
    let client = LivePTYClient()
    let directory = URL.temporaryDirectory.appending(path: "LivePTYClientTests", directoryHint: .isDirectory)

    func spawn(
        _ arguments: [String],
        executable: String = "/bin/sh",
        size: PTYSize = PTYSize(columns: 80, rows: 24)
    ) async throws -> any PTYSession {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try await client.spawn(PTYSpec(
            executable: executable,
            arguments: [executable] + arguments,
            environment: ["PATH": "/usr/bin:/bin", "TERM": "xterm-256color", "PS1": "$ "],
            workingDirectory: directory,
            size: size
        ))
    }

    /// Everything the process writes, until the terminal closes.
    func everything(from session: any PTYSession) async -> String {
        var data = Data()
        for await chunk in session.output { data.append(chunk) }
        return String(decoding: data, as: UTF8.self)
    }

    func poll<T>(_ what: String, _ value: () async -> T?) async throws -> T {
        for _ in 0..<300 {
            if let found = await value() { return found }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw PollTimeout(what: what)
    }

    struct PollTimeout: Error { let what: String }

    @Test func startsInTheWorkingDirectory() async throws {
        let session = try await spawn(["-c", "pwd"])
        let output = await everything(from: session)
        // `realpath`, not `resolvingSymlinksInPath`, which leaves `/var` alone
        // and so disagrees with what the shell prints.
        let real = String(cString: realpath(directory.path(percentEncoded: false), nil)!)
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == real)
    }

    @Test func hasATerminalForItsStandardStreams() async throws {
        let session = try await spawn(["-c", "test -t 0 && test -t 1 && test -t 2 && echo tty"])
        #expect(await everything(from: session).contains("tty"))
    }

    @Test func passesTheEnvironmentItWasGivenAndNoOther() async throws {
        let session = try await spawn(["-c", "echo $TERM:$HOME"])
        #expect(await everything(from: session).trimmingCharacters(in: .whitespacesAndNewlines) == "xterm-256color:")
    }

    @Test func deliversWhatIsWrittenToIt() async throws {
        let session = try await spawn(["-c", "read line; echo got:$line"])
        await session.write(Data("hello\n".utf8))
        #expect(await everything(from: session).contains("got:hello"))
    }

    @Test func startsAtTheSizeItWasAskedFor() async throws {
        let session = try await spawn(["-c", "stty size"], size: PTYSize(columns: 132, rows: 43))
        #expect(await everything(from: session).contains("43 132"))
    }

    @Test func resizesAfterItHasStarted() async throws {
        let session = try await spawn(["-c", "read line; stty size"])
        await session.resize(PTYSize(columns: 100, rows: 30))
        await session.write(Data("\n".utf8))
        #expect(await everything(from: session).contains("30 100"))
    }

    /// `/dev/tty` opens only for a process with a controlling terminal. zsh as
    /// well as `sh`, because `sh` takes the terminal for itself when it starts
    /// and so passes either way.
    @Test(arguments: ["/bin/sh", "/bin/zsh"])
    func theTerminalIsItsControllingTerminal(shell: String) async throws {
        let session = try await spawn(["-c", "exec 3</dev/tty && echo controlling"], executable: shell)
        #expect(await everything(from: session).contains("controlling"))
    }

    /// What tells a full-screen program to redraw: without it, a resize
    /// reaches the terminal and the program never hears of it.
    @Test(arguments: ["/bin/sh", "/bin/zsh"])
    func aResizeSignalsTheProcess(shell: String) async throws {
        let session = try await spawn(
            ["-c", "trap 'stty size; exit' WINCH; echo ready; while :; do sleep 0.05; done"],
            executable: shell
        )
        defer { session.terminate() }
        var output = ""
        var resized = false
        for await chunk in session.output {
            output += String(decoding: chunk, as: UTF8.self)
            if !resized, output.contains("ready") {
                resized = true
                await session.resize(PTYSize(columns: 100, rows: 30))
            }
        }
        #expect(output.contains("30 100"))
    }

    @Test func reportsAnExitCode() async throws {
        let session = try await spawn(["-c", "exit 7"])
        #expect(await session.waitForExit() == 7)
    }

    @Test func reportsASignalAs128PlusItsNumber() async throws {
        let session = try await spawn(["-c", "kill -9 $$"])
        #expect(await session.waitForExit() == 137)
    }

    @Test func waitingAfterTheExitStillAnswers() async throws {
        let session = try await spawn(["-c", "exit 3"])
        _ = await everything(from: session)
        _ = try await poll("exit") { await session.waitForExit() }
        #expect(await session.waitForExit() == 3)
    }

    @Test func terminatingHangsUp() async throws {
        let session = try await spawn(["-c", "sleep 30"])
        session.terminate()
        #expect(await session.waitForExit() == 129)
    }

    /// Waits for `ready`, so the traps are set before the hang-up.
    func spawnReady(_ script: String) async throws -> any PTYSession {
        let session = try await spawn(["-c", "\(script); echo ready; while :; do sleep 0.05; done"])
        var output = ""
        for await chunk in session.output {
            output += String(decoding: chunk, as: UTF8.self)
            if output.contains("ready") { break }
        }
        return session
    }

    @Test func aProcessThatIgnoresTheHangUpIsTerminated() async throws {
        let session = try await spawnReady("trap '' HUP")
        session.terminate()
        #expect(await session.waitForExit() == 143)
    }

    @Test func aProcessThatIgnoresTerminationIsKilled() async throws {
        let session = try await spawnReady("trap '' HUP TERM")
        session.terminate()
        #expect(await session.waitForExit() == 137)
    }

    @Test func terminatingNowDoesNotWaitToAskHarder() async throws {
        let session = try await spawnReady("trap '' HUP")
        let start = ContinuousClock.now
        session.terminateNow()
        #expect(await session.waitForExit() == 143)
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func aFailedStartIsAnError() async throws {
        await #expect(throws: PTYClientError.self) {
            _ = try await client.spawn(PTYSpec(
                executable: "/nonexistent/shell", arguments: ["shell"], environment: [:],
                workingDirectory: directory, size: PTYSize(columns: 80, rows: 24)
            ))
        }
    }

    @Test func aMissingWorkingDirectoryIsAnError() async throws {
        await #expect(throws: PTYClientError.self) {
            _ = try await client.spawn(PTYSpec(
                executable: "/bin/sh", arguments: ["sh"], environment: [:],
                workingDirectory: URL(filePath: "/nonexistent/folder"), size: PTYSize(columns: 80, rows: 24)
            ))
        }
    }

    @Test func theShellIsTheForegroundUntilItRunsSomething() async throws {
        let session = try await spawn(["-i"])
        defer { session.terminate() }

        let idle = try await poll("the shell in front") { await session.foregroundProcess() }
        #expect(idle.isShell)
        #expect(idle.name == "sh")

        await session.write(Data("sleep 30\n".utf8))
        let running = try await poll("sleep in front") {
            await session.foregroundProcess().flatMap { $0.name == "sleep" ? $0 : nil }
        }
        #expect(!running.isShell)
        #expect(running.commandLine == "sleep 30")
    }

    @Test func aLoginShellIsNamedWithoutItsDash() async throws {
        let session = try await client.spawn(PTYSpec(
            executable: "/bin/sh", arguments: ["-sh", "-i"], environment: ["PATH": "/usr/bin:/bin"],
            workingDirectory: directory, size: PTYSize(columns: 80, rows: 24)
        ))
        defer { session.terminate() }
        let process = try await poll("the shell in front") { await session.foregroundProcess() }
        #expect(process.name == "sh")
        #expect(process.isShell)
    }

    @Test func reportsTheDirectoryTheShellIsIn() async throws {
        let session = try await spawn(["-c", "cd /usr; sleep 30"])
        defer { session.terminate() }
        let found = try await poll("the new directory") {
            await session.workingDirectory().flatMap { $0.lastPathComponent == "usr" ? $0 : nil }
        }
        #expect(found.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "usr")
    }

    // MARK: Backpressure

    func live(_ session: any PTYSession) throws -> LivePTYSession {
        try #require(session as? LivePTYSession)
    }

    @Test func aProcessThatIsNotReadIsHeldToTheLimitRatherThanFillingMemory() async throws {
        let session = try await spawn(["-c", "exec yes"])
        defer { session.terminate() }
        let buffer = try live(session).buffer

        _ = try await poll("the buffer to fill") { buffer.isPaused ? true : nil }
        try await Task.sleep(for: .milliseconds(300))
        // One read past the mark at most: the source is paused in the handler
        // that crossed it.
        #expect(buffer.bufferedBytes <= buffer.highWater + 64 * 1024)
    }

    @Test func readingLetsAPausedProcessCarryOn() async throws {
        let session = try await spawn(["-c", "exec yes"])
        defer { session.terminate() }
        let buffer = try live(session).buffer
        _ = try await poll("the buffer to fill") { buffer.isPaused ? true : nil }

        var received = 0
        for await chunk in session.output {
            received += chunk.count
            if received > 8 * buffer.highWater { break }
        }
        #expect(received > 8 * buffer.highWater)
    }

    @Test func aPausedProcessCanStillBeEnded() async throws {
        let session = try await spawn(["-c", "exec yes"])
        let buffer = try live(session).buffer
        _ = try await poll("the buffer to fill") { buffer.isPaused ? true : nil }

        session.terminate()
        #expect(await session.waitForExit() == 129)
        // The output ends too: what was held is handed out, then nothing.
        var received = 0
        for await chunk in session.output { received += chunk.count }
        #expect(received <= buffer.highWater + 64 * 1024)
    }

    @Test func everythingAProcessWritesArrivesInOrderThroughThePauses() async throws {
        // More than the limit several times over, numbered so a lost or
        // repeated piece shows.
        let session = try await spawn(["-c", "i=0; while [ $i -lt 200000 ]; do echo $i; i=$((i+1)); done"])
        var data = Data()
        for await chunk in session.output {
            data.append(chunk)
            // Slower than the process, so the limit is hit.
            if data.count % (256 << 10) < chunk.count { try await Task.sleep(for: .milliseconds(5)) }
        }
        let lines = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.count == 200_000)
        #expect(lines.first == "0")
        #expect(lines.last == "199999")
        #expect(lines.enumerated().allSatisfy { $0.element == String($0.offset) })
    }

    @Test func nothingIsLeftToAskOnceItHasExited() async throws {
        let session = try await spawn(["-c", "exit 0"])
        _ = await session.waitForExit()
        #expect(await session.foregroundProcess() == nil)
        #expect(await session.workingDirectory() == nil)
    }
}

@Suite struct ProcessArgumentsTests {
    /// What `KERN_PROCARGS2` returns: `argc`, the path, padding, the arguments,
    /// then an environment this must not read.
    func layout(argc: Int32, path: String, padding: Int, arguments: [String], environment: [String]) -> [UInt8] {
        var bytes = withUnsafeBytes(of: argc) { Array($0) }
        bytes += Array(path.utf8) + [0]
        bytes += [UInt8](repeating: 0, count: padding)
        for argument in arguments { bytes += Array(argument.utf8) + [0] }
        for entry in environment { bytes += Array(entry.utf8) + [0] }
        return bytes
    }

    @Test func readsTheArgumentsAndNotTheEnvironment() {
        let bytes = layout(
            argc: 3, path: "/usr/bin/swift", padding: 5,
            arguments: ["swift", "test", "--filter"], environment: ["HOME=/Users/x", "TERM=xterm"]
        )
        #expect(ProcessArguments.parse(bytes) == ["swift", "test", "--filter"])
    }

    @Test func keepsAnEmptyArgument() {
        let bytes = layout(argc: 2, path: "/bin/echo", padding: 1, arguments: ["echo", ""], environment: [])
        #expect(ProcessArguments.parse(bytes) == ["echo", ""])
    }

    @Test func refusesABufferThatEndsEarly() {
        let bytes = layout(argc: 3, path: "/bin/echo", padding: 1, arguments: ["echo", "a"], environment: [])
        #expect(ProcessArguments.parse(bytes) == nil)
    }

    @Test func refusesNothingAtAll() {
        #expect(ProcessArguments.parse([]) == nil)
        #expect(ProcessArguments.parse([0, 0, 0, 0]) == nil)
    }

    @Test func readsItsOwnArguments() throws {
        let own = try #require(ProcessArguments.of(getpid()))
        #expect(!own.isEmpty)
    }
}
