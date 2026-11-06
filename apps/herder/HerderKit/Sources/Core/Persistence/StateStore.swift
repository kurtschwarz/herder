import Foundation

/// Where the app keeps its own state.
///
/// Not the user's work: the source of truth for code is the disk and git. This
/// holds which folders are open, which tabs, which folders are expanded — the
/// things that make a relaunch land where the last quit left off, and nothing
/// that could not be rebuilt by looking at a repository.
///
/// Values go in and come out as `Codable`, keyed by a string, so the store
/// knows nothing about what it is holding. That is deliberate: it is what lets
/// the SwiftData implementation be swapped for one writing JSON files without
/// anything above it noticing.
///
/// Snapshots are plain structs rather than the live `@Observable` classes they
/// come from. Never make an `@Observable` class `Codable` directly: the macro's
/// underscored backing storage leaks into the encoded keys.
public protocol StateStore: Sendable {
    /// The value stored under `key`, or `nil` when nothing is.
    ///
    /// Throws only when something is stored and cannot be read back as `Value`.
    /// A caller that would rather start fresh than fail uses ``loadIfReadable``.
    func load<Value: Codable & Sendable>(_ type: Value.Type, forKey key: String) async throws -> Value?

    func save<Value: Codable & Sendable>(_ value: Value, forKey key: String) async throws

    func remove(forKey key: String) async throws
}

extension StateStore {
    /// Like ``load(_:forKey:)``, but `nil` rather than a throw for state that
    /// cannot be decoded.
    ///
    /// The usual response to unreadable app state is to carry on without it: a
    /// snapshot written by a build whose fields have since changed is worth
    /// less than a window that opens. Snapshots carry a `version` and decode
    /// new fields with defaults, so this should be rare; when it happens, the
    /// user loses their tab layout rather than their session.
    public func loadIfReadable<Value: Codable & Sendable>(
        _ type: Value.Type,
        forKey key: String
    ) async -> Value? {
        try? await load(type, forKey: key)
    }
}
