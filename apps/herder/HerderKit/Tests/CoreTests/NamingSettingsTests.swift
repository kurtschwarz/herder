import Foundation
import TestSupport
import Testing

@testable import Core

@Suite @MainActor struct NamingSettingsTests {
    let state = InMemoryStateStore()
    let vault = InMemoryNamingKeyVault()

    @Test func theEndpointDefaultsToMeridianWithNoKey() {
        let settings = NamingSettings(state: state, vault: vault)

        #expect(settings.configuration == NamingConfiguration(endpoint: URL(string: "http://127.0.0.1:3456")!))
    }

    @Test func theEndpointAndKeySurviveARelaunch() async {
        let settings = NamingSettings(state: state, vault: vault)
        settings.setEndpoint("https://api.anthropic.com")
        settings.setAPIKey("sk-x")
        await settings.flushSaves()

        let relaunched = NamingSettings(state: state, vault: vault)
        await relaunched.load()

        #expect(relaunched.configuration == NamingConfiguration(endpoint: URL(string: "https://api.anthropic.com")!, apiKey: "sk-x"))
    }

    @Test func theKeyGoesToTheVaultAndNotToTheState() async throws {
        let settings = NamingSettings(state: state, vault: vault)
        settings.setAPIKey("sk-x")
        settings.setEndpoint("https://example.com")
        await settings.flushSaves()

        #expect(vault.key == "sk-x")
        let stored = try #require(try await state.load(NamingSnapshot.self, forKey: NamingSnapshot.persistenceKey))
        #expect(stored.endpoint == "https://example.com")
    }

    @Test func aBlankKeyIsRemovedFromTheVault() {
        let settings = NamingSettings(state: state, vault: InMemoryNamingKeyVault(key: "old"))
        settings.setAPIKey("  ")

        #expect(settings.configuration.apiKey == nil)
    }

    @Test func anEndpointThatIsNotAURLIsTheDefault() {
        let settings = NamingSettings(state: state, vault: vault)
        settings.setEndpoint("not a url")

        #expect(settings.configuration.endpoint.absoluteString == NamingConfiguration.defaultEndpoint)
    }
}
