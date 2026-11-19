import Core
import Foundation
import Security

/// ``GitHubTokenVault`` over one generic-password item in the login Keychain,
/// owned by the app. herderd never reads it: it is handed the access token.
public struct KeychainGitHubTokenVault: GitHubTokenVault {
    public struct KeychainError: Error, LocalizedError, Equatable {
        public let status: OSStatus

        public var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
        }
    }

    /// The item's service name. A debug build has its own, so a dev build and
    /// an installed release do not overwrite each other's sign-in.
    public static var defaultService: String {
        #if DEBUG
        "ar.schw.herder.github-dev"
        #else
        "ar.schw.herder.github"
        #endif
    }

    private let service: String
    private let account = "github-app-user-tokens"

    public init(service: String = KeychainGitHubTokenVault.defaultService) {
        self.service = service
    }

    private var identity: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() throws -> GitHubTokens? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode(GitHubTokens.self, from: data)
    }

    public func save(_ tokens: GitHubTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let update = SecItemUpdate(identity as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError(status: update) }

        var item = identity
        item[kSecValueData as String] = data
        let add = SecItemAdd(item as CFDictionary, nil)
        guard add == errSecSuccess else { throw KeychainError(status: add) }
    }

    public func delete() throws {
        let status = SecItemDelete(identity as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
