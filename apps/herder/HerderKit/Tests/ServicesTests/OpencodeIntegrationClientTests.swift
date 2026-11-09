import Core
import Foundation
@testable import Services
import Testing

/// Against real folders: a bundle's `opencode` folder and a config folder,
/// both under a temporary directory of the test's own.
@Suite struct LiveOpencodeIntegrationClientTests {
    let root = URL.temporaryDirectory.appending(
        path: "OpencodeIntegrationClientTests-\(UUID().uuidString)", directoryHint: .isDirectory
    )
    var resources: URL { root.appending(path: "Herder.app/Contents/Resources/opencode", directoryHint: .isDirectory) }
    var config: URL { root.appending(path: "config/opencode", directoryHint: .isDirectory) }
    var client: LiveOpencodeIntegrationClient { LiveOpencodeIntegrationClient(resources: resources, config: config) }
    let files = FileManager.default

    init() throws {
        try files.createDirectory(at: resources.appending(path: "themes"), withIntermediateDirectories: true)
        try files.createDirectory(at: resources.appending(path: "plugins/osc-7501"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: resources.appending(path: "themes/herder.json"))
        try Data("".utf8).write(to: resources.appending(path: "plugins/osc-7501/tui.ts"))
    }

    func path(_ url: URL) -> String { url.path(percentEncoded: false) }

    func destination(of item: String) -> String? {
        try? files.destinationOfSymbolicLink(atPath: path(config.appending(path: item)))
    }

    @Test func linksEveryItemIntoAnEmptyConfig() async {
        await client.install()
        for item in OpencodeIntegration.items {
            #expect(destination(of: item) == path(resources.appending(path: item)))
        }
    }

    @Test func leavesTheUsersOwnTheme() async throws {
        let theme = config.appending(path: "themes/herder.json")
        try files.createDirectory(at: theme.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: theme)

        await client.install()
        #expect(destination(of: "themes/herder.json") == nil)
        #expect(try String(contentsOf: theme, encoding: .utf8) == "mine")
    }

    @Test func leavesALinkToACheckout() async throws {
        let checkout = root.appending(path: "checkout/osc-7501", directoryHint: .isDirectory)
        try files.createDirectory(at: checkout, withIntermediateDirectories: true)
        let plugins = config.appending(path: "plugins")
        try files.createDirectory(at: plugins, withIntermediateDirectories: true)
        try files.createSymbolicLink(atPath: path(plugins.appending(path: "osc-7501")), withDestinationPath: path(checkout))

        await client.install()
        #expect(destination(of: "plugins/osc-7501") == path(checkout))
    }

    @Test func replacesABrokenLink() async throws {
        let plugins = config.appending(path: "plugins")
        try files.createDirectory(at: plugins, withIntermediateDirectories: true)
        try files.createSymbolicLink(atPath: path(plugins.appending(path: "osc-7501")), withDestinationPath: "/gone/osc-7501")

        await client.install()
        #expect(destination(of: "plugins/osc-7501") == path(resources.appending(path: "plugins/osc-7501")))
        #expect(try files.contentsOfDirectory(atPath: path(plugins)) == ["osc-7501"])
    }

    @Test func configFollowsXDGConfigHome() {
        let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)
        #expect(path(LiveOpencodeIntegrationClient.configDirectory(environment: [:], home: home)) == "/Users/me/.config/opencode/")
        #expect(path(LiveOpencodeIntegrationClient.configDirectory(environment: ["XDG_CONFIG_HOME": "/xdg"], home: home)) == "/xdg/opencode/")
    }
}
