import Foundation

/// A bag of per-feature UI state that belongs to one checkout.
///
/// Anything that has to survive a workspace switch — which folders are
/// expanded, which tab is selected, where a pane is scrolled to — cannot live
/// in `@State`, because SwiftUI throws that away when the view swaps out.
/// Features put it here instead, on the workspace, where it lasts as long as
/// the workspace does.
///
/// `Core` never learns the concrete types. A feature declares its own and asks
/// for it by type, which is what keeps this from becoming the place every
/// feature's state ends up visible to every other.
@MainActor
public protocol WorkspaceUIState: AnyObject {
    init()
}

/// ``WorkspaceUIState`` that should also survive a relaunch.
///
/// Conform when the state is worth a line in a ``WorkspaceSnapshot``. Most is
/// not: a scroll position restored into a file that has since changed is worse
/// than the top of the file.
@MainActor
public protocol PersistedWorkspaceUIState: WorkspaceUIState {
    /// Where this state sits in ``WorkspaceSnapshot/uiState``. Stable across
    /// builds: renaming the type must not orphan what the user already had.
    static var persistenceKey: String { get }

    func encode() throws -> Data
    func restore(from data: Data) throws
}

extension Workspace {
    /// The UI state of type `S` for this workspace, made on first ask and kept
    /// after that.
    ///
    /// Lazy because a feature that is never opened should cost nothing, and
    /// cached because the whole point is that it outlives the view.
    ///
    /// If a snapshot was restored into this workspace and had state under this
    /// type's key, the new instance gets it here. That is how restoring works
    /// without `Core` knowing a single feature type: the feature asks for its
    /// state, and what the last run wrote is already in it.
    public func uiState<S: WorkspaceUIState>(_ type: S.Type = S.self) -> S {
        let key = ObjectIdentifier(type)
        if let existing = uiStates[key], let typed = existing as? S { return typed }

        let created = S()
        if let persisted = created as? any PersistedWorkspaceUIState {
            let persistenceKey = Swift.type(of: persisted).persistenceKey
            if let data = pendingUIState.removeValue(forKey: persistenceKey) {
                // Unreadable state is dropped rather than thrown: a pane that
                // opens empty beats a pane that refuses to open. Written by an
                // older build, usually.
                try? persisted.restore(from: data)
            }
        }
        uiStates[key] = created
        return created
    }

    /// This workspace as it goes to `StateStore`.
    public var snapshot: WorkspaceSnapshot {
        WorkspaceSnapshot(
            id: id,
            uiState: persistableUIState(),
            diffBase: diffBase.isUncommitted ? nil : diffBase.ref
        )
    }

    /// Takes the UI state out of `snapshot` and holds it until the features ask.
    ///
    /// Held rather than applied, because applying it would mean making one
    /// instance of every state type, and `Core` does not know what those are.
    /// State for a feature the user never opens this session is simply never
    /// claimed — and is written back out unchanged by ``snapshot``, so closing
    /// a workspace without opening a pane does not forget that pane's layout.
    public func restore(from snapshot: WorkspaceSnapshot) {
        pendingUIState = snapshot.uiState
        if let ref = snapshot.diffBase {
            diffBase = GitDiffBase(ref: ref, name: ref, revision: GitDiffBase.head, isResolved: true)
        }
    }

    /// Every piece of UI state worth persisting, encoded, plus anything
    /// restored that nothing has asked for yet.
    ///
    /// Only states that have actually been created are encoded: a feature the
    /// user never opened has nothing new to say, and writing a default for it
    /// would claim it had been looked at.
    private func persistableUIState() -> [String: Data] {
        var encoded = pendingUIState
        for state in uiStates.values {
            guard let state = state as? any PersistedWorkspaceUIState else { continue }
            // A state that cannot encode itself is skipped rather than failing
            // the whole snapshot. Losing one pane's layout beats losing all of
            // them, and the next save will try again.
            guard let data = try? state.encode() else { continue }
            encoded[Swift.type(of: state).persistenceKey] = data
        }
        return encoded
    }
}
