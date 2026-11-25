import Foundation
import Testing

@testable import Core

/// `settings.schema.json` is written by hand and published from `main`, so
/// nothing but this keeps it in step with the keys `UserSettings` reads and
/// the defaults it writes. It is read from the repository: the app carries no
/// copy.
@Suite struct SettingsSchemaTests {
    typealias Object = [String: Any]

    let schema: Object

    init() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent() // CoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // HerderKit
            .deletingLastPathComponent() // apps/herder
            .appending(path: "settings.schema.json")
        schema = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? Object)
    }

    func object(_ value: Any?) throws -> Object {
        try #require(value as? Object)
    }

    func properties(at path: [String]) throws -> Object {
        var node = schema
        for name in path {
            node = try object(try object(node["properties"])[name])
        }
        return try object(node["properties"])
    }

    func names<Keys: CodingKey & CaseIterable>(_ keys: Keys.Type) -> Set<String> {
        Set(keys.allCases.map(\.stringValue))
    }

    @Test func itsIDIsWhereEveryFilePointsItsSchema() {
        #expect(schema["$id"] as? String == UserSettings.schemaURL)
    }

    @Test func everyKeyTheAppReadsIsInTheSchemaAndNoOther() throws {
        #expect(Set(try properties(at: []).keys) == names(UserSettings.RootKeys.self))
        #expect(Set(try properties(at: ["updates"]).keys) == names(UserSettings.UpdatesKeys.self))
        #expect(Set(try properties(at: ["agents"]).keys) == names(UserSettings.AgentsKeys.self))
        #expect(Set(try properties(at: ["providers"]).keys) == names(UserSettings.ProvidersKeys.self))
        #expect(Set(try properties(at: ["providers", "anthropic"]).keys) == names(UserSettings.AnthropicKeys.self))

        let agent = try object(try object(schema["$defs"])["agent"])
        #expect(Set(try object(agent["properties"]).keys) == names(UserSettings.AgentKeys.self))
        #expect(agent["required"] as? [String] == ["id"])
    }

    @Test func everyDefaultIsWhatTheAppWritesForIt() throws {
        let encoded = try object(JSONSerialization.jsonObject(with: Data(UserSettings().encoded(sparse: false).utf8)))
        var checked = 0

        func compare(_ schemaNode: Object, _ value: Any?, at path: String) throws {
            if let expected = schemaNode["default"] {
                let value = try #require(value, "\(path) has a default the app does not write")
                #expect((expected as AnyObject).isEqual(value), "\(path): schema says \(expected), app writes \(value)")
                checked += 1
            }
            guard let children = schemaNode["properties"] as? Object else { return }
            let values = value as? Object
            for (name, child) in children where name != "$schema" {
                try compare(try object(child), values?[name], at: path.isEmpty ? name : "\(path).\(name)")
            }
        }
        try compare(schema, encoded, at: "")

        #expect(checked == 4)
    }

    @Test func anAgentsIDFollowsTheSameRuleAsTheApp() throws {
        let agent = try object(try object(schema["$defs"])["agent"])
        let id = try object(try object(agent["properties"])["id"])
        let pattern = try #require(id["pattern"] as? String)
        let presets = try #require(try object(id["not"])["enum"] as? [String])

        #expect(presets == Agent.presets.map(\.id))
        for candidate in ["aider", "my-aider-2", "My Aider", "", "custom_1", "éa"] {
            let matches = candidate.wholeMatch(of: try Regex(String(pattern.dropFirst().dropLast()))) != nil
            #expect(matches == UserSettings.isValidAgentID(candidate), "\(candidate)")
        }
    }

    @Test func itHoldsNoSecrets() throws {
        let text = try String(decoding: JSONSerialization.data(withJSONObject: schema), as: UTF8.self).lowercased()

        #expect(!text.contains("\"api_key\""))
        #expect(!text.contains("\"token\""))
    }
}
