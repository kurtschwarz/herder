import Clients
import Foundation
import Observation
import Storage

/// The add-workspace modal's state: the folder picked, the name, and whether
/// the store would take them.
///
/// A folder is validated the moment it is picked, so Add is only ever enabled
/// for something that should succeed. `submit()` still validates again, because
/// the folder can change between the pick and the click.
@Observable
public final class AddWorkspaceModel {
    /// Why the picked folder cannot be added.
    public enum Refusal: Equatable {
        case notARepository
        /// A `git worktree add` folder. Worktrees appear under their
        /// repository, so the repository is what to add.
        case linkedWorktree(mainRepository: URL)
        case alreadyOpen
        case failed(String)

        init(_ error: any Error) {
            switch error as? WorkspaceStoreError {
            case .notAGitRepository: self = .notARepository
            case .isLinkedWorktree(let main): self = .linkedWorktree(mainRepository: main)
            case .alreadyOpen: self = .alreadyOpen
            case nil: self = .failed(error.localizedDescription)
            }
        }
    }

    private let store: WorkspaceStore
    private let picker: any FolderPickerClient

    /// What git made of `folder`, set only once the store has accepted it.
    private var kind: GitRepositoryKind?

    /// Once the user has typed a name, picking another folder leaves it alone.
    private var isNameEdited = false

    public private(set) var folder: URL?
    public private(set) var name = ""
    public private(set) var refusal: Refusal?
    public private(set) var isSubmitting = false

    public var canAdd: Bool { kind != nil && refusal == nil && !isSubmitting }

    public init(store: WorkspaceStore, picker: any FolderPickerClient) {
        self.store = store
        self.picker = picker
    }

    /// Opens the folder picker and validates what comes back. Cancelling leaves
    /// everything as it was.
    public func browse(startingAt start: URL? = nil) async {
        guard let url = await picker.pickFolder(startingAt: start) else { return }
        await select(url)
    }

    /// Reopens the picker where the refused worktree's repository lives. The
    /// app cannot take the repository itself: the sandbox only let it see the
    /// folder the user chose.
    public func chooseMainRepository() async {
        guard case .linkedWorktree(let main) = refusal else { return }
        await browse(startingAt: main)
    }

    public func editName(_ name: String) {
        self.name = name
        isNameEdited = true
    }

    /// Adds the workspace. Returns whether it was added; on `false`, `refusal`
    /// says why.
    public func submit() async -> Bool {
        guard canAdd, let folder else { return false }
        isSubmitting = true
        defer { isSubmitting = false }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await store.add(url: folder, name: trimmed.isEmpty ? nil : trimmed)
            return true
        } catch {
            kind = nil
            refusal = Refusal(error)
            return false
        }
    }

    private func select(_ url: URL) async {
        folder = url
        kind = nil
        refusal = nil

        do {
            let kind = try await store.validate(url: url)
            // Another pick landed while this one was being checked.
            guard folder == url else { return }
            self.kind = kind
            if !isNameEdited {
                name = WorkspaceStore.defaultName(for: url.standardizedFileURL, kind: kind)
            }
        } catch {
            guard folder == url else { return }
            refusal = Refusal(error)
            if !isNameEdited { name = "" }
        }
    }
}
