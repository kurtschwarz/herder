import Core
import Foundation
import Observation

/// The files that differ from the diff base, kept current while the card is on
/// screen.
@Observable
final class ChangedFilesModel {
    private let workspace: Workspace
    private var registration: Workspace.Registration?
    private var generation = 0

    /// `nil` until the first read finishes.
    private(set) var files: [GitChangedFile]?

    init(workspace: Workspace) {
        self.workspace = workspace
    }

    var base: GitDiffBase { workspace.diffBase }

    func start() async {
        registration?.cancel()
        registration = workspace.observe(onChange: { [weak self] in
            Task { await self?.reload() }
        })
        await reload()
    }

    func stop() {
        registration?.cancel()
        registration = nil
    }

    /// Reads again. An answer that arrives after a newer question was asked is
    /// dropped, so a slow read cannot put an old base's files back.
    func reload() async {
        generation += 1
        let mine = generation
        let read = await workspace.changedFiles()
        guard mine == generation, files != read else { return }
        files = read
    }

    func url(of file: GitChangedFile) -> URL {
        workspace.root.appending(file.path).url
    }
}
