import Core
import Testing

@Suite struct AppVersionTests {
    @Test func readsAReleaseBuildsPlist() {
        let version = AppVersion(info: [
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "412",
            AppVersion.commitKey: "e87cd6e",
        ])
        #expect(version == AppVersion(version: "0.1.0", build: "412", commit: "e87cd6e"))
        #expect(version.display == "0.1.0 (412)")
    }

    /// `$(HERDER_GIT_COMMIT)` expands to nothing when a build does not set it.
    @Test func anEmptyCommitIsNone() {
        let version = AppVersion(info: [
            "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1", AppVersion.commitKey: "",
        ])
        #expect(version.commit == nil)
    }
}
