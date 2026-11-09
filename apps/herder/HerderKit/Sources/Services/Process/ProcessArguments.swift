import Darwin
import Foundation

/// Reading what a process was started with, which is how a terminal says what
/// is running in it. The kernel keeps `argv` and does not mind who asks, for a
/// process of the same user.
enum ProcessArguments {
    /// `argv` of `pid`, or `nil` if it is gone or its arguments cannot be read.
    static func of(_ pid: Int32) -> [String]? {
        bytes(of: pid).flatMap(parse)
    }

    /// The environment `pid` was started with, or `nil` if it is gone or
    /// cannot be read. What it was given, not what it has set since.
    static func environment(of pid: Int32) -> [String: String]? {
        bytes(of: pid).flatMap(parseEnvironment)
    }

    private static func bytes(of pid: Int32) -> [UInt8]? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return Array(buffer.prefix(size))
    }

    /// The layout `KERN_PROCARGS2` returns: a native-endian `argc`, the
    /// executable's path, padding NULs, then `argc` NUL-terminated strings,
    /// then the environment, which is not wanted here.
    static func parse(_ bytes: [UInt8]) -> [String]? {
        var reader = Reader(bytes)
        guard let argc = reader.argc else { return nil }
        var arguments: [String] = []
        while arguments.count < argc, let next = reader.next() { arguments.append(next) }
        return arguments.count == argc ? arguments : nil
    }

    /// After the arguments, `NAME=value` strings up to an empty one. What
    /// follows that is the kernel's, not the process's.
    static func parseEnvironment(_ bytes: [UInt8]) -> [String: String]? {
        var reader = Reader(bytes)
        guard let argc = reader.argc else { return nil }
        for _ in 0..<argc { guard reader.next() != nil else { return nil } }
        var environment: [String: String] = [:]
        while let entry = reader.next(), !entry.isEmpty {
            guard let equals = entry.firstIndex(of: "=") else { continue }
            environment[String(entry[..<equals])] = String(entry[entry.index(after: equals)...])
        }
        return environment
    }

    /// Walks the NUL-terminated strings after the executable's path.
    private struct Reader {
        let bytes: [UInt8]
        var index = MemoryLayout<Int32>.size
        let argc: Int?

        init(_ bytes: [UInt8]) {
            self.bytes = bytes
            guard bytes.count > MemoryLayout<Int32>.size else {
                argc = nil
                return
            }
            let count = Int(bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
            argc = count > 0 ? count : nil
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            while index < bytes.count, bytes[index] == 0 { index += 1 }
        }

        mutating func next() -> String? {
            guard index < bytes.count else { return nil }
            var end = index
            while end < bytes.count, bytes[end] != 0 { end += 1 }
            defer { index = end + 1 }
            return String(decoding: bytes[index..<end], as: UTF8.self)
        }
    }

    /// The directory `pid` is in, or `nil` if it is gone.
    static func workingDirectory(of pid: Int32) -> URL? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        return path.isEmpty ? nil : URL(filePath: path, directoryHint: .isDirectory)
    }
}
