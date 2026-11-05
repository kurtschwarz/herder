import Core
import Foundation
import SwiftData

/// ``StateStore`` over SwiftData, keeping each value as a JSON blob in a
/// ``StoredState`` row.
///
/// Transitional. The target is `FileStateStore` writing JSON under Application
/// Support, and the blob shape is what makes that swap cheap: the bytes in a
/// row are already what a file would hold, so the move is a new implementation
/// of this protocol rather than a migration of anything above it.
///
/// An `actor` because it is a stateful service and because the alternative is
/// worse: a `ModelContext` is not `Sendable`, so it has to stay inside one
/// isolation domain. Each call makes its own context rather than holding one.
/// Contexts are cheap, and a long-lived one here would be a second place
/// holding unsaved changes to a store the app's `mainContext` is also writing.
public actor SwiftDataStateStore: StateStore {
    private let container: ModelContainer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(container: ModelContainer) {
        self.container = container
    }

    public func load<Value: Codable & Sendable>(
        _ type: Value.Type,
        forKey key: String
    ) throws -> Value? {
        guard let data = try row(forKey: key)?.data else { return nil }
        return try decoder.decode(Value.self, from: data)
    }

    public func save<Value: Codable & Sendable>(_ value: Value, forKey key: String) throws {
        let data = try encoder.encode(value)
        let context = ModelContext(container)

        // `key` is unique, so a save replaces. Updating the row in place rather
        // than deleting and inserting keeps `StoredState` free of a window in
        // which the key exists twice, which the unique constraint would refuse.
        if let existing = try Self.row(forKey: key, in: context) {
            existing.data = data
            existing.updatedAt = .now
        } else {
            context.insert(StoredState(key: key, data: data))
        }
        try context.save()
    }

    public func remove(forKey key: String) throws {
        let context = ModelContext(container)
        guard let existing = try Self.row(forKey: key, in: context) else { return }
        context.delete(existing)
        try context.save()
    }

    private func row(forKey key: String) throws -> StoredState? {
        try Self.row(forKey: key, in: ModelContext(container))
    }

    private static func row(forKey key: String, in context: ModelContext) throws -> StoredState? {
        var descriptor = FetchDescriptor<StoredState>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
