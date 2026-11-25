import Foundation
import Observation

/// Where the naming call goes: an endpoint, kept in the user's settings, and
/// an optional API key, kept in the Keychain and never in the settings file.
///
/// App-wide: Settings edits it and every window's New order card reads it.
///
/// The annotation is explicit because `Core` keeps the nonisolated default.
@MainActor
@Observable
public final class NamingSettings {
    public private(set) var apiKey = ""

    /// Why the key could not be read or kept, until the next try.
    public private(set) var keyError: String?

    @ObservationIgnored private let store: UserSettingsStore
    @ObservationIgnored private let vault: (any NamingKeyVault)?

    /// `vault` is `nil` where there is no Keychain to keep a key in, as in a
    /// test: the key then lasts as long as the app.
    public init(settings: UserSettingsStore, vault: (any NamingKeyVault)?) {
        self.store = settings
        self.vault = vault
    }

    /// What the endpoint field says, which may not be a URL while it is being
    /// typed.
    public var endpoint: String {
        store.settings.anthropicEndpoint
    }

    /// What a naming call is made with now. An endpoint that is not a URL is
    /// the default, which is what a call falls back on rather than failing.
    public var configuration: NamingConfiguration {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: trimmed).flatMap { $0.scheme == nil || $0.host() == nil ? nil : $0 }
            ?? URL(string: NamingConfiguration.defaultEndpoint)!
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return NamingConfiguration(endpoint: url, apiKey: key.isEmpty ? nil : key)
    }

    /// Reads the key. The endpoint is the settings store's, loaded with it.
    public func load() async {
        do {
            apiKey = try vault?.load() ?? ""
        } catch {
            keyError = error.localizedDescription
        }
    }

    public func setEndpoint(_ value: String) {
        store.update { $0.anthropicEndpoint = value }
    }

    public func setAPIKey(_ value: String) {
        guard value != apiKey else { return }
        apiKey = value
        keyError = nil
        do {
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try vault?.delete()
            } else {
                try vault?.save(value)
            }
        } catch {
            keyError = error.localizedDescription
        }
    }

    /// Waits for every save asked for so far.
    public func flushSaves() async {
        await store.flushWrites()
    }
}
