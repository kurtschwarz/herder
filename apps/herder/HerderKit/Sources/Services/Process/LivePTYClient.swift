import Core
import Darwin
import Foundation

/// Runs processes on a pseudo-terminal with `openpty` and `posix_spawn`.
///
/// Not `forkpty`: `fork` is unavailable to Swift, and running Swift between a
/// fork and an exec in a process with threads is not safe. `posix_spawn` does
/// the same work in one call, with `POSIX_SPAWN_SETSID` making the child the
/// leader of a session of its own and opening the terminal by name making it
/// that session's controlling terminal.
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

        // Neither end may leak into the child: it is given the terminal by
        // name below, and a master it could write to would be a way to type
        // into itself.
        _ = fcntl(master, F_SETFD, FD_CLOEXEC)
        _ = fcntl(slave, F_SETFD, FD_CLOEXEC)
        _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)

        var nameBuffer = [CChar](repeating: 0, count: 128)
        guard ttyname_r(slave, &nameBuffer, nameBuffer.count) == 0 else {
            close(master)
            throw .openFailed(errno)
        }
        let slavePath = String(decoding: nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)

        switch Self.start(spec, slavePath: slavePath) {
        case .success(let pid):
            return LivePTYSession(master: master, pid: pid)
        case .failure(let error):
            close(master)
            throw error
        }
    }

    private static func start(_ spec: PTYSpec, slavePath: String) -> Result<pid_t, PTYClientError> {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, slavePath, O_RDWR, 0)
        posix_spawn_file_actions_adddup2(&actions, 0, 1)
        posix_spawn_file_actions_adddup2(&actions, 0, 2)
        posix_spawn_file_actions_addchdir(&actions, spec.workingDirectory.path(percentEncoded: false))

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var defaults = sigset_t()
        sigfillset(&defaults)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setsigmask(&attributes, &mask)
        // CLOEXEC_DEFAULT: the child gets the three descriptors above and
        // nothing else the app happens to have open.
        let flags = POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT
        posix_spawnattr_setflags(&attributes, Int16(flags))

        let argv = spec.arguments.map { strdup($0) } + [nil]
        let envp = spec.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, spec.executable, &actions, &attributes, argv, envp)
        return result == 0 ? .success(pid) : .failure(.spawnFailed(result))
    }
}
