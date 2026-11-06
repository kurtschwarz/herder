import Core
import Foundation
import Observation

/// The add-repository modal's state: the folder picked, the name, and whether
/// the window's list would take them.
///
/// A folder is validated the moment it is picked, so Add is only ever enabled
/// for something that should succeed. `submit()` still validates again, because
/// the folder can change between the pick and the click.
@Observable
final class AddRepositoryModel {
    /// Why the picked folder cannot be added.
    enum Refusal: Equatable {
        case notARepository
        /// A `git worktree add` folder. Worktrees appear under their
        /// repository, so the repository is what to add.
        case linkedWorktree(mainRepository: URL)
        case alreadyOpen
        case failed(String)

        init(_ error: any Error) {
            switch error as? RepositoryStoreError {
            case .notAGitRepository: self = .notARepository
            case .isLinkedWorktree(let main): self = .linkedWorktree(mainRepository: main)
            case .alreadyOpen: self = .alreadyOpen
            case nil: self = .failed(error.localizedDescription)
            }
        }
    }

    private let repositories: WindowRepositories
    private let picker: any FolderPickerClient

    /// What git made of `folder`, set only once the store has accepted it.
    private var kind: GitRepositoryKind?

    /// Once the user has typed a name, picking another folder leaves it alone.
    private var isNameEdited = false

    private(set) var folder: URL?
    private(set) var name = ""
    private(set) var refusal: Refusal?
    private(set) var isSubmitting = false

    var canAdd: Bool { kind != nil && refusal == nil && !isSubmitting }

    init(repositories: WindowRepositories, picker: any FolderPickerClient) {
        self.repositories = repositories
        self.picker = picker
    }

    /// Opens the folder picker and validates what comes back. Cancelling leaves
    /// everything as it was.
    func browse(startingAt start: URL? = nil) async {
        guard let url = await picker.pickFolder(startingAt: start) else { return }
        await select(url)
    }

    /// Reopens the picker where the refused worktree's repository lives. The
    /// app cannot take the repository itself: the sandbox only let it see the
    /// folder the user chose.
    func chooseMainRepository() async {
        guard case .linkedWorktree(let main) = refusal else { return }
        await browse(startingAt: main)
    }

    func editName(_ name: String) {
        self.name = name
        isNameEdited = true
    }

    /// Adds the repository. Returns whether it was added; on `false`, `refusal`
    /// says why.
    func submit() async -> Bool {
        guard canAdd, let folder else { return false }
        isSubmitting = true
        defer { isSubmitting = false }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await repositories.add(url: folder, name: trimmed.isEmpty ? nil : trimmed)
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
            let kind = try await repositories.validate(url: url)
            // Another pick landed while this one was being checked.
            guard folder == url else { return }
            self.kind = kind
            if !isNameEdited {
                name = RepositoryStore.defaultName(for: url.standardizedFileURL, kind: kind)
            }
        } catch {
            guard folder == url else { return }
            refusal = Refusal(error)
            if !isNameEdited { name = "" }
        }
    }
}
