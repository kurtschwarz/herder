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
/// After the handshake the connection stays open for as long as this client
/// lives, which is what keeps the daemon from exiting idle while the app runs.
/// Nothing is sent over it yet.
///
/// A daemon older than every protocol version the app speaks, and owning no
/// sessions, is ended and replaced with the bundled one (see
/// ``DaemonWire/mayReplace(afterReply:)``). That is what an update meets: the
/// app is replaced and the daemon it started is not, and without this every
/// git call would fail until the old daemon idled out.
public final class LiveDaemonClient: DaemonClient {
    public enum DaemonRequestError: Error, Equatable {
        /// Nothing answered, or what answered would not shake hands.
        case unreachable
        /// The daemon took the request and then closed or timed out.
        case noReply
    }

    /// Starts `executable` with `arguments`, detached, and returns its pid.
    public typealias Launch = @Sendable (_ executable: URL, _ arguments: [String]) throws -> pid_t

    /// Ends the old daemon at `pid` and returns once it has gone, or `false`
    /// when it was not ended.
    public typealias Terminate = @Sendable (_ pid: pid_t) -> Bool

    private let socketURL: URL
    private let executable: URL?
    private let client: String
    private let daemonArguments: [String]
    private let launch: Launch
    private let terminate: Terminate
    private let startTimeout: Duration

    private let launched = Mutex<[pid_t]>([])

    /// The open connection that tells the daemon a client is here.
    private let held = Mutex<Int32?>(nil)

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
        launch: @escaping Launch = LiveDaemonClient.spawnDetached,
        terminate: @escaping Terminate = LiveDaemonClient.terminateDaemon
    ) {
        self.socketURL = socket
        self.executable = executable
        self.client = client
        self.daemonArguments = daemonArguments
        self.startTimeout = startTimeout
        self.launch = launch
        self.terminate = terminate
    }

    deinit { disconnect() }

    /// Lets go of the connection, so the daemon may exit once it is idle. The
    /// app never needs this: it holds the connection until it quits.
    func disconnect() {
        held.withLock { descriptor in
            if let current = descriptor { close(current) }
            descriptor = nil
        }
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

        if let answer = handshake(path: path) {
            guard let old = answer.replaceable, executable != nil, terminate(old) else { return answer.status }
        }

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
            if let answer = handshake(path: path) { return answer.status }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return .unavailable(reason: "herderd was started but did not answer.")
    }

    /// One connection per request: the handshake, the request, the reply, and
    /// the connection closed. Requests then run side by side without anything
    /// in the app tying a reply to a request, which the daemon's workers would
    /// otherwise answer out of order.
    ///
    /// A daemon that will not shake hands is asked once more after
    /// ``connect()``, which may have replaced an old one with the bundled one.
    @concurrent
    public func request(_ payload: Data) async throws -> Data {
        let path = socketURL.path(percentEncoded: false)
        guard Self.fits(path) else { throw DaemonRequestError.unreachable }

        if let reply = try exchange(payload, path: path) { return reply }
        guard case .connected = await connect(), let reply = try exchange(payload, path: path) else {
            throw DaemonRequestError.unreachable
        }
        return reply
    }

    /// `nil` when nothing answers or what answers will not shake hands.
    private func exchange(_ payload: Data, path: String) throws -> Data? {
        guard let descriptor = Self.open(path, receiveTimeout: Self.requestTimeout) else { return nil }
        defer { close(descriptor) }

        guard Self.writeAll(descriptor, DaemonWire.hello(client: client)),
              let welcome = Self.readFrame(descriptor),
              case .connected = DaemonWire.status(fromReply: welcome)
        else { return nil }

        guard Self.writeAll(descriptor, DaemonWire.frame(payload)), let reply = Self.readFrame(descriptor) else {
            throw DaemonRequestError.noReply
        }
        return reply
    }

    /// Long enough for git to walk a large repository.
    private static let requestTimeout = 120

    // MARK: - Socket

    private static func fits(_ path: String) -> Bool {
        path.utf8CString.count <= MemoryLayout.size(ofValue: sockaddr_un().sun_path)
    }

    /// `nil` when nothing is listening, so the caller can start the daemon.
    /// Once something is, every outcome is a status, and `replaceable` is the
    /// pid of a daemon this app may end and replace.
    private func handshake(path: String) -> (status: DaemonStatus, replaceable: pid_t?)? {
        guard let descriptor = Self.open(path, receiveTimeout: 2) else { return nil }
        var keep = false
        defer { if !keep { close(descriptor) } }
        // Read now: once an incompatible daemon has answered it closes, and
        // the system no longer says who it was.
        let peer = Self.peer(of: descriptor)

        guard Self.writeAll(descriptor, DaemonWire.hello(client: client)) else {
            return (.unavailable(reason: "herderd closed the connection."), nil)
        }
        guard let header = Self.readExactly(descriptor, DaemonWire.headerSize),
              let length = DaemonWire.payloadLength(header: header),
              let payload = Self.readExactly(descriptor, length)
        else {
            return (.unavailable(reason: "herderd did not answer."), nil)
        }
        let status = DaemonWire.status(fromReply: payload)
        if DaemonWire.mayReplace(afterReply: payload) {
            return (status, peer)
        }
        if case .connected = status {
            keep = true
            // A retry replaces the connection it already holds.
            held.withLock { previous in
                if let old = previous { close(old) }
                previous = descriptor
            }
        }
        return (status, nil)
    }

    /// The process that listens on the other end of the socket, if it runs as
    /// this user.
    private static func peer(of descriptor: Int32) -> pid_t? {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(descriptor, &uid, &gid) == 0, uid == getuid() else { return nil }
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 0 else { return nil }
        return pid
    }

    private static func open(_ path: String, receiveTimeout: Int) -> Int32? {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }

        var timeout = timeval(tv_sec: receiveTimeout, tv_usec: 0)
        var sendTimeout = timeval(tv_sec: 2, tv_usec: 0)
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))
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

    private static func readFrame(_ descriptor: Int32) -> Data? {
        guard let header = readExactly(descriptor, DaemonWire.headerSize),
              let length = DaemonWire.payloadLength(header: header)
        else { return nil }
        return readExactly(descriptor, length)
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

    // MARK: - Replacing an old daemon

    /// Ends `pid` if it is a herderd: `SIGTERM`, then `SIGKILL` if it is still
    /// there after two seconds. A pid is checked against its executable's name
    /// first, so a pid reused by something else since the handshake is never
    /// signalled.
    public static let terminateDaemon: Terminate = { pid in
        guard isDaemon(pid) else { return false }
        return end(pid)
    }

    /// Whether the process at `pid` is running a binary named `herderd`.
    static func isDaemon(_ pid: pid_t) -> Bool {
        guard pid > 0, pid != getpid() else { return false }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(filePath: path).lastPathComponent == "herderd"
    }

    /// Signals `pid` to end and waits for it to be gone.
    static func end(_ pid: pid_t) -> Bool {
        func gone(within seconds: Double) -> Bool {
            let deadline = Date.now.addingTimeInterval(seconds)
            while Date.now < deadline {
                if kill(pid, 0) != 0, errno == ESRCH { return true }
                usleep(20_000)
            }
            return false
        }
        guard kill(pid, SIGTERM) == 0 || errno == ESRCH else { return false }
        if gone(within: 2) { return true }
        kill(pid, SIGKILL)
        return gone(within: 1)
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
