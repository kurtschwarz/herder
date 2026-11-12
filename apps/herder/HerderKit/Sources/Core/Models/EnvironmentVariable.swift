import Foundation

/// One row of an agent's environment as it is edited in Settings.
///
/// A dictionary cannot hold a row that is half typed: one with no name yet, or
/// one whose name another row has. So the editor works on rows, each with an id
/// of its own, and ``dictionary(from:)`` keeps what can be set.
public struct EnvironmentVariable: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var value: String

    public init(id: UUID = UUID(), name: String, value: String) {
        self.id = id
        self.name = name
        self.value = value
    }

    /// Whether the name is one a shell would accept: letters, digits and
    /// underscores, not starting with a digit.
    public var hasValidName: Bool {
        Self.isValid(name: name)
    }

    public static func isValid(name: String) -> Bool {
        guard let first = name.unicodeScalars.first, !("0"..."9").contains(first) else { return false }
        return name.unicodeScalars.allSatisfy {
            ("A"..."Z").contains($0) || ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_"
        }
    }

    /// The rows for an agent's variables, sorted by name.
    public static func rows(from environment: [String: String]?) -> [EnvironmentVariable] {
        (environment ?? [:])
            .sorted { $0.key < $1.key }
            .map { EnvironmentVariable(name: $0.key, value: $0.value) }
    }

    /// The variables the rows set, or `nil` for none. A row with no name or an
    /// invalid one sets nothing, and of rows that share a name the last wins.
    public static func dictionary(from rows: [EnvironmentVariable]) -> [String: String]? {
        var environment: [String: String] = [:]
        for row in rows {
            let name = row.name.trimmingCharacters(in: .whitespaces)
            guard isValid(name: name) else { continue }
            environment[name] = row.value
        }
        return environment.isEmpty ? nil : environment
    }
}
