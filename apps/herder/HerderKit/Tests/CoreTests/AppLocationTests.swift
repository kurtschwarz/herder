import Core
import Foundation
import Testing

@Suite struct AppLocationTests {
    func location(_ path: String) -> AppLocation {
        AppLocation(bundle: URL(filePath: path, directoryHint: .isDirectory))
    }

    @Test func applicationsIsSettled() {
        #expect(location("/Applications/Herder.app") == .settled)
        #expect(location("/Users/me/Applications/Herder.app") == .settled)
    }

    @Test func aBuildFolderIsSettled() {
        #expect(location("/Users/me/Library/Developer/Xcode/DerivedData/Herder-abc/Build/Products/Debug/Herder.app") == .settled)
    }

    @Test func aMountedImageIsNot() {
        #expect(location("/Volumes/Herder/Herder.app") == .diskImage)
    }

    @Test func aTranslocatedDownloadIsNot() {
        #expect(location("/private/var/folders/x1/abc/T/AppTranslocation/5D2C-11AA/d/Herder.app") == .translocated)
    }
}
