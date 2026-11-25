import Foundation
import TestSupport
import Testing

@testable import Core

@Suite @MainActor struct NamingSettingsTests {
    let file = InMemorySettingsFileClient()
    let vault = InMemoryNamingKeyVault()

    func store() -> UserSettingsStore {
        UserSettingsStore(file: file, clock: VirtualClockClient())
    }

    @Test func theEndpointDefaultsToMeridianWithNoKey() {
        let settings = NamingSettings(settings: store(), vault: vault)

        #expect(settings.configuration == NamingConfiguration(endpoint: URL(string: "http://127.0.0.1:3456")!))
    }

    @Test func theEndpointAndKeySurviveARelaunch() async {
        let settings = NamingSettings(settings: store(), vault: vault)
        settings.setEndpoint("https://api.anthropic.com")
        settings.setAPIKey("sk-x")
        await settings.flushSaves()

        let reloaded = store()
        await reloaded.load()
        let relaunched = NamingSettings(settings: reloaded, vault: vault)
        await relaunched.load()

        #expect(relaunched.configuration == NamingConfiguration(endpoint: URL(string: "https://api.anthropic.com")!, apiKey: "sk-x"))
    }

    @Test func theKeyGoesToTheVaultAndNotToTheSettingsFile() async throws {
        let settings = NamingSettings(settings: store(), vault: vault)
        settings.setAPIKey("sk-x")
        settings.setEndpoint("https://example.com")
        await settings.flushSaves()

        #expect(vault.key == "sk-x")
        let written = try #require(file.contents)
        #expect(try UserSettings.decode(written).anthropicEndpoint == "https://example.com")
        #expect(!written.contains("sk-x"))
    }

    @Test func aBlankKeyIsRemovedFromTheVault() {
        let settings = NamingSettings(settings: store(), vault: InMemoryNamingKeyVault(key: "old"))
        settings.setAPIKey("  ")

        #expect(settings.configuration.apiKey == nil)
    }

    @Test func anEndpointThatIsNotAURLIsTheDefault() {
        let settings = NamingSettings(settings: store(), vault: vault)
        settings.setEndpoint("not a url")

        #expect(settings.configuration.endpoint.absoluteString == NamingConfiguration.defaultEndpoint)
    }
}
