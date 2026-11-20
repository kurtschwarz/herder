import Core
import Foundation
import Security

/// ``NamingKeyVault`` over one generic-password item in the login Keychain.
public struct KeychainNamingKeyVault: NamingKeyVault {
    public struct KeychainError: Error, LocalizedError, Equatable {
        public let status: OSStatus

        public var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
        }
    }

    /// The item's service name. A debug build has its own, so a dev build and
    /// an installed release do not overwrite each other's key.
    public static var defaultService: String {
        #if DEBUG
        "ar.schw.herder.naming-dev"
        #else
        "ar.schw.herder.naming"
        #endif
    }

    private let service: String
    private let account = "naming-api-key"

    public init(service: String = KeychainNamingKeyVault.defaultService) {
        self.service = service
    }

    private var identity: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() throws -> String? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status: status) }
        return String(decoding: data, as: UTF8.self)
    }

    public func save(_ key: String) throws {
        let data = Data(key.utf8)
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
