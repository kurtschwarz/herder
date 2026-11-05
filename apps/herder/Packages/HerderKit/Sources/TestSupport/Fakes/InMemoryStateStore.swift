#if DEBUG
import Core
import Foundation

/// ``StateStore`` in a dictionary.
///
/// Encodes and decodes for real rather than holding the values themselves, so a
/// snapshot that cannot survive a round trip fails here as it would in the app.
/// A fake that stashed the original object would pass while the real store threw.
public actor InMemoryStateStore: StateStore {
    private var blobs: [String: Data] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {}

    /// Every key written, so a test can assert what was saved without decoding.
    public var keys: Set<String> { Set(blobs.keys) }

    public func load<Value: Codable & Sendable>(
        _ type: Value.Type,
        forKey key: String
    ) throws -> Value? {
        guard let data = blobs[key] else { return nil }
        return try decoder.decode(Value.self, from: data)
    }

    public func save<Value: Codable & Sendable>(_ value: Value, forKey key: String) throws {
        blobs[key] = try encoder.encode(value)
    }

    public func remove(forKey key: String) {
        blobs[key] = nil
    }

    /// Puts bytes under `key` that are not valid for whatever a test will ask
    /// for, so the "unreadable state is skipped rather than fatal" path can be
    /// exercised.
    public func seedUnreadable(forKey key: String) {
        blobs[key] = Data("not json".utf8)
    }
}
#endif
