import Core
import Darwin
import Foundation
import Synchronization

/// Reaches herderd over its Unix socket, starting it from the app bundle when
/// nothing is listening.
///
/// The daemon is spawned in its own session with its output discarded, so that
/// quitting or killing the app, or a Ctrl-C in the terminal `just dev` runs in,
/// leaves it alone. See ADR 0001 for why it is started this way and not by
/// launchd.
///
/// This slice only completes the handshake and lets go of the connection;
/// nothing is sent over it yet.
public final class LiveDaemonClient: DaemonClient {
    /// Starts `executable` with `arguments`, detached, and returns its pid.
    public typealias Launch = @Sendable (_ executable: URL, _ arguments: [String]) throws -> pid_t

    private let socketURL: URL
    private let executable: URL?
    private let client: String
    private let daemonArguments: [String]
    private let launch: Launch
    private let startTimeout: Duration

    private let launched = Mutex<[pid_t]>([])

    /// The processes this client started, so a test can end them.
    var launchedPIDs: [pid_t] { launched.withLock { $0 } }

    /// - Parameters:
    ///   - socket: where the daemon listens.
    ///   - executable: the daemon to start if nothing answers, or `nil` if
    ///     there is none to start.
    ///   - client: who is asking, for the daemon's log.
    ///   - daemonArguments: extra arguments for a daemon this client starts, such
    ///     as a shorter `--idle-timeout` for a test.
    public init(
        socket: URL,
        executable: URL?,
        client: String,
        daemonArguments: [String] = [],
        startTimeout: Duration = .seconds(5),
        launch: @escaping Launch = LiveDaemonClient.spawnDetached
    ) {
        self.socketURL = socket
        self.executable = executable
        self.client = client
        self.daemonArguments = daemonArguments
        self.startTimeout = startTimeout
        self.launch = launch
    }

    /// The socket's file name. A debug build has its own, so a dev build and an
    /// installed release each start and reach their own daemon.
    public static var socketName: String {
        #if DEBUG
        "herderd-dev.sock"
        #else
        "herderd.sock"
        #endif
    }

    /// Where the daemon's socket is: beside the app's own state.
    public static func socketURL() throws -> URL {
        try FileStateStore.liveRoot().appending(path: socketName)
    }

    @concurrent
    public func connect() async -> DaemonStatus {
        let path = socketURL.path(percentEncoded: false)
        guard Self.fits(path) else {
            return .unavailable(reason: "The socket path is too long for a Unix socket: \(path)")
        }

        if let status = handshake(path: path) { return status }

        guard let executable else {
            return .unavailable(reason: "herderd is not running and this build does not include it.")
        }
        do {
            let pid = try launch(executable, ["--socket", path] + daemonArguments)
            launched.withLock { $0.append(pid) }
        } catch {
            return .unavailable(reason: "Could not start herderd: \(error.localizedDescription)")
        }

        let deadline = ContinuousClock.now + startTimeout
        while ContinuousClock.now < deadline {
            if let status = handshake(path: path) { return status }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return .unavailable(reason: "herderd was started but did not answer.")
    }

    // MARK: - Socket

    private static func fits(_ path: String) -> Bool {
        path.utf8CString.count <= MemoryLayout.size(ofValue: sockaddr_un().sun_path)
    }

    /// `nil` when nothing is listening, so the caller can start the daemon.
    /// Once something is, every outcome is a status.
    private func handshake(path: String) -> DaemonStatus? {
        guard let descriptor = Self.open(path) else { return nil }
        defer { close(descriptor) }

        guard Self.writeAll(descriptor, DaemonWire.hello(client: client)) else {
            return .unavailable(reason: "herderd closed the connection.")
        }
        guard let header = Self.readExactly(descriptor, DaemonWire.headerSize),
              let length = DaemonWire.payloadLength(header: header),
              let payload = Self.readExactly(descriptor, length)
        else {
            return .unavailable(reason: "herderd did not answer.")
        }
        return DaemonWire.status(fromReply: payload)
    }

    private static func open(_ path: String) -> Int32? {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }

        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = path.utf8CString.map { UInt8(bitPattern: $0) }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    private static func writeAll(_ descriptor: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if written <= 0 { return false }
                offset += written
            }
            return true
        }
    }

    private static func readExactly(_ descriptor: Int32, _ count: Int) -> Data? {
        var data = Data(count: count)
        let complete = data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < count {
                let received = read(descriptor, buffer.baseAddress! + offset, count - offset)
                if received <= 0 { return false }
                offset += received
            }
            return true
        }
        return complete ? data : nil
    }

    // MARK: - Starting the daemon

    /// `posix_spawn` with `POSIX_SPAWN_SETSID`: a new session, so a signal sent
    /// to the app's process group never reaches it.
    public static let spawnDetached: Launch = { executable, arguments in
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)

        let path = executable.path(percentEncoded: false)
        let argv = ([path] + arguments).map { strdup($0) } + [nil]
        let envp = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, path, &actions, &attributes, argv, envp)
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        return pid
    }
}
