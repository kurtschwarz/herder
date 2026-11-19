import Core
import Foundation
@testable import Services
import Testing

/// Against the real login Keychain, under a service name of its own that each
/// test deletes.
@Suite(.timeLimit(.minutes(1))) struct KeychainGitHubTokenVaultTests {
    let vault = KeychainGitHubTokenVault(service: "ar.schw.herder.tests.\(UUID().uuidString)")

    func tokens(_ name: String) -> GitHubTokens {
        GitHubTokens(
            accessToken: "access-\(name)", refreshToken: "refresh-\(name)",
            accessExpiresAt: Date(timeIntervalSince1970: 1_700_000_000),
            refreshExpiresAt: Date(timeIntervalSince1970: 1_715_000_000)
        )
    }

    @Test func nothingStoredIsNil() throws {
        #expect(try vault.load() == nil)
    }

    @Test func savedTokensReadBackAndASecondSaveReplacesThem() throws {
        defer { try? vault.delete() }

        try vault.save(tokens("one"))
        #expect(try vault.load() == tokens("one"))

        try vault.save(tokens("two"))
        #expect(try vault.load() == tokens("two"))
    }

    @Test func deletingRemovesTheItemAndDeletingAgainIsNotAnError() throws {
        try vault.save(tokens("one"))

        try vault.delete()
        try vault.delete()

        #expect(try vault.load() == nil)
    }
}
