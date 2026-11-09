import Core
import Testing

@Suite struct OpencodeIntegrationTests {
    @Test func linksWhereNothingIs() {
        #expect(OpencodeIntegration.shouldLink(over: .nothing))
    }

    @Test func leavesTheUsersOwnFile() {
        #expect(!OpencodeIntegration.shouldLink(over: .item))
    }

    /// What `just install` makes: a developer's edits must keep reaching
    /// opencode.
    @Test func leavesALinkToACheckout() {
        let checkout = "/Users/me/code/herder/packages/opencode-theme/herder.json"
        #expect(!OpencodeIntegration.shouldLink(over: .link(destination: checkout, resolves: true)))
    }

    /// A copy of the app that has since been updated or moved.
    @Test func replacesALinkIntoAHerderBundle() {
        let old = "/Users/me/Applications/Herder.app/Contents/Resources/opencode/themes/herder.json"
        #expect(OpencodeIntegration.shouldLink(over: .link(destination: old, resolves: true)))
    }

    @Test func replacesABrokenLink() {
        #expect(OpencodeIntegration.shouldLink(over: .link(destination: "/gone/herder.json", resolves: false)))
    }
}
