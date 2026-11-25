import Core
import Foundation
import Testing

@Suite struct HomeRelativePathTests {
    let home = URL(filePath: "/Users/kurt", directoryHint: .isDirectory)

    @Test func theHomeFolderIsATilde() {
        #expect(HomeRelativePath.label(for: home, home: home) == "~")
    }

    @Test func aFolderUnderItIsRelative() {
        #expect(HomeRelativePath.label(for: URL(filePath: "/Users/kurt/dev/app/"), home: home) == "~/dev/app")
    }

    @Test func aFolderOutsideItIsLeftAlone() {
        #expect(HomeRelativePath.label(for: URL(filePath: "/usr/local"), home: home) == "/usr/local")
    }

    @Test func aSiblingWithTheSamePrefixIsNotUnderIt() {
        #expect(HomeRelativePath.label(for: URL(filePath: "/Users/kurtis/dev"), home: home) == "/Users/kurtis/dev")
    }

    @Test func theComponentsStartAtTheTildeOrTheRoot() {
        let settings = URL(filePath: "/Users/kurt/.config/herder/settings.json")

        #expect(HomeRelativePath.components(for: settings, home: home) == ["~", ".config", "herder", "settings.json"])
        #expect(HomeRelativePath.components(for: URL(filePath: "/etc/hosts"), home: home) == ["/", "etc", "hosts"])
    }
}
