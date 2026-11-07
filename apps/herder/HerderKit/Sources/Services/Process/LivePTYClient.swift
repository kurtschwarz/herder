import Core
import Darwin
import Foundation
import PTYSpawn

/// Runs processes on a pseudo-terminal with `openpty` and `herder_pty_spawn`.
///
/// Not `forkpty`: `fork` is unavailable to Swift, and running Swift between a
/// fork and an exec in a process with threads is not safe. Not `posix_spawn`
/// alone either: it cannot make the terminal the child's controlling one.
/// `PTYSpawn` is the few lines of C between the two. See there for why.
public struct LivePTYClient: PTYClient {
    public init() {}

    public func spawn(_ spec: PTYSpec) async throws(PTYClientError) -> any PTYSession {
        var size = winsize(
            ws_row: spec.size.rows, ws_col: spec.size.columns, ws_xpixel: 0, ws_ypixel: 0
        )
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, &size) == 0 else {
            throw .openFailed(errno)
        }
        defer { close(slave) }

        // Neither end may leak into the child: it is given the slave as its
        // standard streams, and a master it could write to would be a way to
        // type into itself.
        _ = fcntl(master, F_SETFD, FD_CLOEXEC)
        _ = fcntl(slave, F_SETFD, FD_CLOEXEC)
        _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)

        switch Self.start(spec, slave: slave) {
        case .success(let pid):
            return LivePTYSession(master: master, pid: pid)
        case .failure(let error):
            close(master)
            throw error
        }
    }

    private static func start(_ spec: PTYSpec, slave: Int32) -> Result<pid_t, PTYClientError> {
        let argv = spec.arguments.map { strdup($0) } + [nil]
        let envp = spec.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let result = herder_pty_spawn(
            &pid, spec.executable, argv, envp, spec.workingDirectory.path(percentEncoded: false), slave
        )
        return result == 0 ? .success(pid) : .failure(.spawnFailed(result))
    }
}
