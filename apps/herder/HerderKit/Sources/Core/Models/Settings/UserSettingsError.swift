import Foundation

/// What is wrong with `settings.json`, in words that say where.
///
/// A `DecodingError` names a coding path and a Swift type; this names the key
/// as the file spells it, `agents.custom[0].id`, and the JSON type it wanted.
public struct UserSettingsError: Error, Equatable, LocalizedError {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    init(_ error: DecodingError) {
        switch error {
        case .typeMismatch(let type, let context):
            self.init(message: "\(Self.place(context.codingPath)) should be \(Self.kind(of: type)).")
        case .valueNotFound(let type, let context):
            self.init(message: "\(Self.place(context.codingPath)) should be \(Self.kind(of: type)), not null.")
        case .keyNotFound(let key, let context):
            self.init(message: "\(Self.place(context.codingPath + [key])) is missing.")
        case .dataCorrupted(let context) where context.codingPath.isEmpty:
            let detail = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            self.init(message: "It isn\u{2019}t valid JSON" + (detail.map { ": \($0)" } ?? "."))
        case .dataCorrupted(let context):
            self.init(message: "\(Self.place(context.codingPath)) is not valid: \(context.debugDescription)")
        @unknown default:
            self.init(message: error.localizedDescription)
        }
    }

    public var errorDescription: String? { message }

    private static func place(_ path: [any CodingKey]) -> String {
        var place = ""
        for key in path {
            if let index = key.intValue {
                place += "[\(index)]"
            } else {
                place += place.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return place.isEmpty ? "The file" : place
    }

    private static func kind(of type: Any.Type) -> String {
        switch type {
        case is String.Type: "a string"
        case is Bool.Type: "true or false"
        case is [String: String].Type: "an object of strings"
        case is Int.Type, is Double.Type: "a number"
        default:
            String(describing: type).hasPrefix("Array") ? "an array" : "an object"
        }
    }
}
