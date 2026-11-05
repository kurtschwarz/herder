import Core
import CryptoKit
import Foundation

/// ``StateStore`` over JSON files under Application Support. The only
/// implementation there is.
///
/// It replaced a SwiftData-backed store that kept each snapshot as a JSON blob
/// in a row. Because the bytes in a row were already exactly what a file holds,
/// the swap was a new type behind the same protocol rather than a change to
/// anything above it — which is also why removing SwiftData afterwards was a
/// deletion and not a rewrite.
///
/// ```
/// ~/Library/Application Support/Herder/
/// ├── state.json                       # AppSnapshot
/// └── workspaces/<name>-<hash>.json    # WorkspaceSnapshot, one per workspace
/// ```
///
/// **Nothing here debounces.** The callers already do, and they differ on
/// purpose: a workspace waits 400ms after its UI state settles, and the
/// repository list writes immediately on every change because each addition
/// mints a security-scoped bookmark that cannot be remade. A debounce in here
/// would override that distinction and put the one thing that must not wait
/// behind the same timer as the one that should.
///
/// An `actor`, like the store it replaces, so two saves to one key cannot
/// interleave. The I/O runs on the actor's executor, which no UI touches.
public actor FileStateStore: StateStore {
    private let root: URL

    /// Sorted keys and newlines, because the point of files over a SQLite blob
    /// is being able to read and diff what the app remembers.
    ///
    /// **No date or data strategy is set, deliberately.** The import copies
    /// bytes written by `JSONEncoder`'s defaults, so this must decode with the
    /// same defaults: dates as seconds since 1970, `Data` as base64. Setting a
    /// strategy here would make every migrated snapshot unreadable.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/Herder/`. Used by the app.
    public static func live() throws -> FileStateStore {
        FileStateStore(root: try liveRoot())
    }

    public static func liveRoot() throws -> URL {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Herder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public func load<Value: Codable & Sendable>(
        _ type: Value.Type,
        forKey key: String
    ) throws -> Value? {
        let data: Data
        do {
            data = try Data(contentsOf: url(forKey: key))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // Nothing stored. Anything else — a permission problem, an
            // unreadable volume — is a real failure and is not swallowed into
            // "there was none", which would look like state the user never had.
            return nil
        }
        return try decoder.decode(Value.self, from: data)
    }

    public func save<Value: Codable & Sendable>(_ value: Value, forKey key: String) throws {
        try write(try encoder.encode(value), to: url(forKey: key))
    }

    public func remove(forKey key: String) throws {
        do {
            try FileManager.default.removeItem(at: url(forKey: key))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Removing what is not there is what the caller wanted anyway.
        }
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // `.atomic` writes a neighbouring temp file and renames it over the
        // target, so a crash mid-write leaves the previous state rather than
        // half of the new one. That matters most for the one file holding
        // bookmarks nobody can remake.
        try data.write(to: url, options: .atomic)
    }

    /// Where `key` is kept.
    ///
    /// `nonisolated` because it reads only `root`, which is immutable, so
    /// naming a file does not need to enter the actor.
    nonisolated func url(forKey key: String) -> URL {
        // The one key spelled out here, because `ARCHITECTURE.md` names the
        // file rather than deriving it. Everything else is mechanical.
        if key == AppSnapshot.persistenceKey {
            return root.appending(path: "state.json")
        }

        if let path = key.dropping(prefix: Self.workspacePrefix) {
            return root
                .appending(path: "workspaces", directoryHint: .isDirectory)
                .appending(path: "\(Self.fileName(for: path, fullKey: key)).json")
        }

        return root.appending(path: "\(Self.fileName(for: key, fullKey: key)).json")
    }

    private static let workspacePrefix = "workspace:"

    /// A file name for a key that is usually an absolute path.
    ///
    /// The readable part is the last path component, so `workspaces/` can be
    /// looked through by eye. The suffix is what makes it correct: two
    /// worktrees called `main` under different repositories share a last
    /// component, and a deep enough path would otherwise run past the 255-byte
    /// limit on a file name and fail the save.
    ///
    /// **SHA-256 and not `hashValue`.** Swift's hashing is seeded per process,
    /// so a file written on one launch would be looked for under a different
    /// name on the next, and every workspace would silently forget its state.
    private static func fileName(for readablePart: String, fullKey: String) -> String {
        let digest = SHA256.hash(data: Data(fullKey.utf8))
        let hash = digest.prefix(6).map { String(format: "%02x", $0) }.joined()

        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let last = readablePart.split(separator: "/").last.map(String.init) ?? readablePart
        // Leading dots dropped so a folder like `.config` does not become a
        // hidden file that nobody looking in the directory can see.
        let readable = String(last.filter(allowed.contains)).drop(while: { $0 == "." }).prefix(40)

        return readable.isEmpty ? hash : "\(readable)-\(hash)"
    }
}

private extension String {
    /// The rest of the string after `prefix`, or `nil` when it does not start
    /// with it.
    func dropping(prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
