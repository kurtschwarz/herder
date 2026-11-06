import Darwin
import Foundation

/// Reading what a process was started with, which is how a terminal says what
/// is running in it. The kernel keeps `argv` and does not mind who asks, for a
/// process of the same user.
enum ProcessArguments {
    /// `argv` of `pid`, or `nil` if it is gone or its arguments cannot be read.
    static func of(_ pid: Int32) -> [String]? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parse(Array(buffer.prefix(size)))
    }

    /// The layout `KERN_PROCARGS2` returns: a native-endian `argc`, the
    /// executable's path, padding NULs, then `argc` NUL-terminated strings,
    /// then the environment, which is not wanted here.
    static func parse(_ bytes: [UInt8]) -> [String]? {
        guard bytes.count > MemoryLayout<Int32>.size else { return nil }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0 else { return nil }

        var index = MemoryLayout<Int32>.size
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        while index < bytes.count, bytes[index] == 0 { index += 1 }

        var arguments: [String] = []
        while arguments.count < Int(argc), index < bytes.count {
            var end = index
            while end < bytes.count, bytes[end] != 0 { end += 1 }
            arguments.append(String(decoding: bytes[index..<end], as: UTF8.self))
            index = end + 1
        }
        return arguments.count == Int(argc) ? arguments : nil
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
