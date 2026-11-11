import Foundation

/// A file path as it was written in terminal output, with the place in it that
/// was named, if any: `src/foo.swift:42:7`.
public struct TerminalPathReference: Equatable, Sendable {
    /// As written, without the line and column.
    public var path: String
    public var line: Int?
    public var column: Int?

    public init(path: String, line: Int?, column: Int?) {
        self.path = path
        self.line = line
        self.column = column
    }

    /// Where the path points. Relative paths are taken from `directory`, and
    /// do not resolve without one. Whether anything is there is not asked.
    public func resolved(against directory: URL?, home: URL) -> URL? {
        if path.hasPrefix("/") { return URL(filePath: path).standardizedFileURL }
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appending(path: String(path.dropFirst(2))).standardizedFileURL }
        return directory?.appending(path: path).standardizedFileURL
    }
}
