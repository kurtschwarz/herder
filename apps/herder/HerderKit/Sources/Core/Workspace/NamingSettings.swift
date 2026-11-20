import Foundation
import Observation

/// Where the naming call goes: an endpoint, kept with the app's state, and an
/// optional API key, kept in the Keychain.
///
/// App-wide: Settings edits it and every window's New order card reads it.
///
/// The annotation is explicit because `Core` keeps the nonisolated default.
@MainActor
@Observable
public final class NamingSettings {
    /// What the endpoint field says, which may not be a URL while it is being
    /// typed.
    public private(set) var endpoint = NamingConfiguration.defaultEndpoint
    public private(set) var apiKey = ""

    /// Why the key could not be read or kept, until the next try.
    public private(set) var keyError: String?

    @ObservationIgnored private let state: any StateStore
    @ObservationIgnored private let vault: (any NamingKeyVault)?
    @ObservationIgnored private var saving: Task<Void, Never>?

    /// `vault` is `nil` where there is no Keychain to keep a key in, as in a
    /// test: the key then lasts as long as the app.
    public init(state: any StateStore, vault: (any NamingKeyVault)?) {
        self.state = state
        self.vault = vault
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

    public func load() async {
        if let snapshot = await state.loadIfReadable(NamingSnapshot.self, forKey: NamingSnapshot.persistenceKey) {
            endpoint = snapshot.endpoint
        }
        do {
            apiKey = try vault?.load() ?? ""
        } catch {
            keyError = error.localizedDescription
        }
    }

    public func setEndpoint(_ value: String) {
        guard value != endpoint else { return }
        endpoint = value
        let snapshot = NamingSnapshot(endpoint: value)
        let previous = saving
        saving = Task { [state] in
            await previous?.value
            try? await state.save(snapshot, forKey: NamingSnapshot.persistenceKey)
        }
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
        await saving?.value
    }
}
