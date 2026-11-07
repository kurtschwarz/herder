import Core
import Foundation

/// Runs a command line through the user's login shell, as their terminal
/// would, so that a program is found where they would find it.
public struct LiveCommandClient: CommandClient {
    private let environment: [String: String]
    private let timeout: Duration

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: Duration = .seconds(10)
    ) {
        self.environment = environment
        self.timeout = timeout
    }

    @concurrent
    public func output(of line: String, in directory: URL) async -> String? {
        let shell = ShellLaunch.shell(from: environment)
        let process = Process()
        process.executableURL = URL(filePath: shell)
        // Interactive as well as login, for the reason `ShellLaunch.command`
        // gives.
        process.arguments = ["-l", "-i", "-c", line]
        process.environment = environment
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output

        do {
            try process.run()
        } catch {
            return nil
        }

        // A program that hangs must not hold its caller: it is ended, and
        // what it wrote by then is not trusted.
        let deadline = Task {
            try? await Task.sleep(for: timeout)
            if process.isRunning { process.terminate() }
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()

        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
