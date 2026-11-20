import Core
import Foundation
@testable import Services
import Testing

/// Against real processes, orphaned the way a crash orphans an agent: by
/// their parent exiting.
@Suite(.serialized, .timeLimit(.minutes(1))) struct LiveLeftoverAgentClientTests {
    let directory = URL.temporaryDirectory.appending(
        path: "LeftoverAgentClientTests-\(UUID().uuidString)", directoryHint: .isDirectory
    )

    /// Starts `sleep`, marked with `mark` (`$$` for its own pid), ignoring
    /// HUP and TERM, under a shell that exits at once. Returns its pid once
    /// it is `sleep`: the pid is written before the `exec`, and until then
    /// the process has no mark to find.
    ///
    /// A copy of `sleep`, signed again: the kernel hides the environment of
    /// Apple's own binaries, and an agent is never one of those.
    func orphan(mark: String) async throws -> pid_t {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "pid")
        let sleep = directory.appending(path: "sleep")
        let script = directory.appending(path: "agent.sh")
        try """
            trap '' HUP TERM
            cp /bin/sleep '\(sleep.path)' && codesign -s - -f '\(sleep.path)' 2>/dev/null || exit 1
            echo $$ > '\(file.path)'
            exec env \(AgentMark.variable)=\(mark) '\(sleep.path)' 30
            """.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "/bin/sh \"$0\" &", script.path]
        try process.run()
        process.waitUntilExit()

        for _ in 0..<200 {
            if let text = try? String(contentsOf: file, encoding: .utf8),
               let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
               LiveLeftoverAgentClient.processes().first(where: { $0.pid == pid })?.parent == 1,
               ProcessArguments.environment(of: pid)?[AgentMark.variable] != nil {
                return pid
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw Orphaned()
    }

    struct Orphaned: Error {}

    func isRunning(_ pid: pid_t) -> Bool {
        LiveLeftoverAgentClient.processes().contains { $0.pid == pid }
    }

    @Test func endsAnOrphanMarkedWithItsOwnPid() async throws {
        let pid = try await orphan(mark: "$$")
        await LiveLeftoverAgentClient().endLeftovers()
        for _ in 0..<40 where isRunning(pid) { try await Task.sleep(for: .milliseconds(25)) }
        #expect(!isRunning(pid))
    }

    @Test func leavesOneThatOnlyInheritedTheMark() async throws {
        let pid = try await orphan(mark: "1")
        defer { kill(pid, SIGKILL) }
        await LiveLeftoverAgentClient().endLeftovers()
        #expect(isRunning(pid))
    }
}
