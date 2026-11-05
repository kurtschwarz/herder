import Core
import Foundation
import Synchronization
import Testing

@testable import AppFeature

/// Which workspace a window shows.
///
/// Per window, which is the point: this used to be a pair of properties on the
/// repository list's model backed by `UserDefaults`, so every window in the app
/// necessarily agreed — and two windows on different checkouts of one
/// repository is what Herder is for.
@Suite @MainActor struct WindowModelTests {
    private let api = WorkspaceID(PathKey(canonical: "/code/api"))
    private let web = WorkspaceID(PathKey(canonical: "/code/web"))

    @Test func aNewWindowShowsNothing() {
        #expect(WindowModel().activeWorkspaceID == nil)
    }

    @Test func activatingShows() {
        let window = WindowModel()
        window.activate(api)
        #expect(window.activeWorkspaceID == api)
    }

    @Test func activatingNothingClears() {
        let window = WindowModel(activeWorkspaceID: api)
        window.activate(nil)
        #expect(window.activeWorkspaceID == nil)
    }

    /// `withObservationTracking`'s handler is `@Sendable`, so the count cannot
    /// be a captured `var`. A `Mutex` rather than an `@unchecked Sendable` box:
    /// the compiler's objection is reasonable and cheap to satisfy.
    private func changeCount(_ body: (WindowModel) -> Void, on window: WindowModel) -> Int {
        let changes = Mutex(0)
        withObservationTracking {
            _ = window.activeWorkspaceID
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        body(window)
        return changes.withLock { $0 }
    }

    /// Switching drives the work of opening a workspace, so asking for what is
    /// already showing must not look like a change.
    @Test func activatingWhatIsAlreadyShowingIsNotAChange() {
        let window = WindowModel(activeWorkspaceID: api)
        #expect(changeCount({ $0.activate(api) }, on: window) == 0)
    }

    @Test func switchingIsNoticed() {
        let window = WindowModel(activeWorkspaceID: api)
        #expect(changeCount({ $0.activate(web) }, on: window) == 1)
    }

    /// Two windows, two answers. The whole reason this type exists.
    @Test func twoWindowsShowDifferentWorkspaces() {
        let first = WindowModel()
        let second = WindowModel()

        first.activate(api)
        second.activate(web)

        #expect(first.activeWorkspaceID == api)
        #expect(second.activeWorkspaceID == web)
    }
}
