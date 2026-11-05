# Herder Re-alignment Plan

**Goal:** move the existing Herder codebase to the architecture in `ARCHITECTURE.md` incrementally. This is not a rewrite. The app keeps building and working after every task.

Read `ARCHITECTURE.md` and `realignment/survey.md` before this file. The first describes where we're going, the second describes where we actually are, and this file describes how we get from one to the other.

Herder lives at `apps/herder/` in a monorepo. Paths here follow the same convention as `ARCHITECTURE.md`: relative to `apps/herder/`, except paths starting with `packages/`, which are relative to the repo root. Run commands from `apps/herder/`.

## Rules of engagement

1. Read `docs/ARCHITECTURE.md` and `docs/realignment/survey.md` in full before starting any task.
2. One task at a time, on its own branch: `realign/p<N>-<slug>` (for example `realign/p5-filetree`).
3. **Move first, change later.** A task that moves code must not change behavior. If you spot a bug or a better design while moving, write it in `docs/realignment/notes.md` and keep going.
4. Every task ends green. See "Definition of done".
5. Keep diffs reviewable. If a task grows past roughly 1,500 changed lines (not counting pure file moves), stop and propose a split.
6. Use `git mv` for moves so history follows the files.
7. Never delete user data, SwiftData stores, or files outside the repo.
8. Update the progress checklist at the bottom of this file in the same PR.
9. Commit messages: `realign(p<N>): <what changed>`.
10. **Leave `packages/syntax-highlighter` where it is.** Don't move, rename, or restructure it. Tasks in this plan only change how Swift consumes it.
11. **Stay inside `apps/herder/`.** The only thing outside it you may read is `packages/syntax-highlighter`, and you don't change it. Don't touch other apps, other packages, or repo-root config (root CI, workspace files, root `justfile`, root `README.md`). If a task seems to need that, stop and ask.
12. **Never rename a `@Model` class, and never change a schema without running `just test`.** The class name is the stored entity name, so a rename makes the user's store an unknown model version and every row unreachable. `StorageTests` opens a committed V1 fixture store for this; it is the only test that can catch it. See `ARCHITECTURE.md`, "Never rename a `@Model` class".
13. **`Herder.xcodeproj` is generated.** Run `just project` after changing anything under `Herder/` or `UITests/`. Files under `Packages/HerderKit` need no regeneration.
14. **Keep `AGENTS.md` true.** `apps/herder/AGENTS.md` describes the structure as it is today. Any task that invalidates part of it updates it in the same PR.

## Stop and ask Kurt when

- The survey contradicts an assumption in this plan or in `ARCHITECTURE.md`.
- A change would alter user-visible behavior.
- A change would drop data that can't be recreated from disk or git — in particular anything in `Repository` (see "Decisions", D6).
- You need concurrency escape hatches (`@unchecked Sendable`, `nonisolated(unsafe)`) in more than a couple of places within one task.
- Two features turn out to be genuinely coupled and would need merging or redesigning.
- Something in `ARCHITECTURE.md` looks wrong for this codebase.
- A task seems to need changes inside `packages/syntax-highlighter`, especially to its public API.
- A task seems to need changes anywhere outside `apps/herder/`.

## Definition of done (every task)

- [ ] The app builds: `just build`
- [ ] Swift tests pass: `just test`
- [ ] Rust tests and lint pass: `just test` in `packages/syntax-highlighter` (`cargo test` **and** `cargo clippy --all-targets -- -D warnings`)
- [ ] `just check` passes (from Phase 2 on)
- [ ] No new compiler or concurrency warnings. The baseline is zero.
- [ ] `AGENTS.md` still describes the structure accurately
- [ ] Progress checklist updated
- [ ] PR description lists anything added to `docs/realignment/notes.md`

`swift test` does not work in this repo and `xcodebuild -scheme Herder` needs the generated project first. Use the `just` recipes. See the survey, §2.

## Manual smoke test (Kurt runs this at review gates)

Written against what the app can actually do. Extend it as features land.

1. Launch the app. Add a repository. Its worktrees appear under it in the sidebar.
2. Select a worktree. The file tree appears. Click a file: it opens in the editor with syntax highlighting.
3. Expand folders. Create a file, rename it, delete it in a terminal. The tree and the git marks keep up.
4. Create a new worktree from the new-session modal. It appears under its repository.
5. Rename and reorder repositories. Collapse one.
6. Switch between worktrees. The file tree's expanded folders and selection come back as they were. *(after Phase 4)*
7. Quit and relaunch. Repositories, their names, their order, the collapsed ones and the selected worktree all restore. *(after Phase 4)*
8. Open a second window. Each window shows its own worktree. *(after Phase 4)*

## Parallelization

```
P2 → P3 → P4 ─┬─► P5  one agent per feature, in parallel worktrees
              ├─► P6  parallel with P5 (highlighter boundary)
              └─► P7  any time after P4 (optional)
                            └─► P8 after everything else
```

Phases 0 and 1 are done. Phases 2 through 4 are sequential, because each one reshapes code the next one depends on. From Phase 5 on, run agents in separate worktrees. `Package.swift` is the merge hotspot: each agent adds only its own target entry and rebases before opening a PR.

---

## Decisions

The survey raised ten questions. These are the answers; they are settled and not to be relitigated. `ARCHITECTURE.md` has been amended to match.

- **D1. Paths.** The package stays at `Packages/HerderKit/` and the app sources at `Herder/`. The docs were wrong, not the repo. `check-boundaries.sh` uses `SRC="Packages/HerderKit/Sources"` and `APP_DIR="Herder"`.
- **D2. XCFramework.** Keep the vendored copy: `just syntax` builds the crate's XCFramework and copies it into `Packages/HerderKit/Vendor/`, and the `.binaryTarget` path stays inside the package. SwiftPM never depends on Cargo's output directory.
- **D3. `ExplorerFeature` → `FileTreeFeature`.** Rename the module, the folder and the types (`ExplorerModel` → `FileTreeModel`, `ExplorerRow` → `FileTreeRow`, and so on) in the Phase 5 FileTree task. One vocabulary.
- **D4. `Workspace` is a checkout.** `WorktreeState` → `Workspace`, `WorktreeStateStore` → `WorkspaceRegistry`, and the SwiftData `@Model Workspace` → `Repository`. Herder keeps both levels: a `Repository` is what the user adopts and names, a `Workspace` is one of its worktrees. `ARCHITECTURE.md`'s state hierarchy now shows both.
- **D5. The workspace list becomes `RepositoriesFeature`** at `Sources/Features/Repositories/`. It is **app-scoped**: it acts on the `WorkspaceRegistry` rather than on one `Workspace`, because it is the feature that picks which workspace the others run in. `ARCHITECTURE.md` now splits the feature list into workspace-scoped and app-scoped for this reason.
- **D6. `Repository` data gets migrated, never dropped.** The security-scoped bookmark cannot be regenerated without the user re-picking the folder, and the name and order are the user's work. Phase 4 migrates the rows into snapshots rather than deleting the table, and Phase 7 does not start fresh. Where the bookmark lives under `FileStateStore` is still open — decide before Phase 7.
- **D7. `AGENTS.md` points at `ARCHITECTURE.md`.** The four rules it held that were not in the architecture doc (`PathKey` over raw `URL`; tokens only applied to the string they were found in; a reload that finds the same text changes nothing; token kinds and colours kept apart) have been moved into `ARCHITECTURE.md`. `AGENTS.md` keeps only the "where a new file goes" table and a pointer. The root `README.md` is left until Phase 8, then asked about.
- **D8. The composition root is `AppFeature`, not the Xcode target.** `Herder/` holds `@main` and resources and links one product. `AppFeature` moves to `Sources/App/` and is the one HerderKit module that may import `Services`. `AppEnvironment` there constructs the live services, so the app target no longer links them.
- **D9. Phase 4 only moves what exists.** No `DocumentStore`, `AgentSessionStore`, tabs, dirty state or saving: those features don't exist, and building them is product work, not realignment. Phase 4 is now the workspace rename, UI state, snapshots, restoration and per-window active workspace. The smoke test above is rewritten to match.
- **D12. `WindowModel` stays in the App target**, and the repository list reaches the window through an action rather than the other way round. Reading needs nothing new: a feature takes `@Environment(Workspace.self)` and gets whichever workspace the window resolved, so nothing ever asks "which one is active?" — which is what stops two windows disagreeing. Writing goes through `OpenWorkspaceAction` in `Core`, supplied by App as an environment value, shaped like SwiftUI's own `openWindow`. The `@Entry` declaring the key lives in `DesignSystem`, because `Core` may not import SwiftUI and App setting a key declared inside one feature would be worse. `DesignSystem` therefore gains a dependency on `Core`, which the template did not have.
- **D11. `WorkspaceID` is the folder's canonical path**, wrapping `PathKey`, not a `UUID`. A workspace is a folder, the registry already keys on the path, and a generated id would need persisting beside the path and keeping in step with it. `WorkspaceSnapshot` therefore has no separate `root` field — the id is the path — which is one change to `ARCHITECTURE.md`'s example. The other is that the example is now labelled as the shape it grows into: `openTabs`, `activeTab` and `agentSessions` arrive with their features, per D9. **Made while implementing 4b rather than asked; reverse it if you disagree.**
- **D10. Smaller corrections** are all folded into `ARCHITECTURE.md`: `just test` not `swift test`, clippy is part of green, `PhosphorSwift` is in the `Package.swift` template, `UITests/` and the generated project are in the layout diagram, `NonisolatedNonsendingByDefault` is in the concurrency section, offsets are already UTF-16 from the crate, and the bindings are hand-written rather than generated. The untracked `default.profraw` droppings are a `.gitignore` line in Phase 8.

---

## Phase 0: Survey (read-only) — done

`docs/realignment/survey.md`. Taken at `74346ad`.

---

## Phase 1: Swift 6 language mode — already done, nothing to do

The survey found every target in Swift 6 mode with zero concurrency warnings, per-target default isolation already configured, no singletons, and only three escape hatches, each already justified in a comment. `project.yml` sets `SWIFT_STRICT_CONCURRENCY: complete`.

Phase 1 is skipped under its own first line. The three escape hatches and two `DispatchQueue` uses get `// CONCURRENCY:` comments in Phase 8.

---

## Phase 2: Core, Services, and boundary checks

**Goal:** the target module layout exists. Pure value types live in `Core`, service implementations live in `Services`, fakes live in `TestSupport`, and boundary checks run.

HerderKit already exists, so this phase **renames and splits** rather than creating from nothing. The existing modules map like this:

| Today | Becomes |
|---|---|
| `Models` | `Core/Models/` |
| `Clients/*/\<Name>Client.swift` (protocols) | `Core/Services/` |
| `Clients/*/Live*.swift` | `Services/<Area>/` |
| value types declared in `Clients/` | `Core/Models/` |
| `ClientsTestSupport` | `TestSupport/Fakes/` |
| `Syntax/{SyntaxToken,SyntaxTokenKind,SourceText}.swift` | `Core/Models/` |
| `Syntax/SyntaxHighlighter.swift` | `Core/Services/` |
| `Syntax/TreeSitterHighlighter.swift` | `Services/Highlighting/` |
| `Worktrees` | `Core/Workspace/` (Phase 4) and `Core/Models/` |
| `Storage` | `Services/Persistence/` |
| `DesignSystem` | unchanged |

**Steps:**

1. Add `Core`, `Services` and `TestSupport` targets to `Package.swift` alongside the existing ones, using the template in `ARCHITECTURE.md`. Keep the `HerderSyntaxFFI` binary target exactly as it is (D2).
2. `git mv` the value types (no UI, no I/O, no SwiftData) into `Core/Models/`, and the service protocols into `Core/Services/`. Make them `public` and `Sendable` as needed. **Do not move the `@Model` type.** `Core` takes the `core` swift settings, so stores that arrive in Phase 4 need explicit `@MainActor`.
3. `git mv` the `Live*` implementations into `Services/<Area>/`: `LiveFileClient` → `Services/FileSystem/`, `LiveGitClient` → `Services/Git/`, `LiveFileWatcherClient` → `Services/FileSystem/`, `LiveBookmarkClient` and `LiveFolderPickerClient` → `Services/FileSystem/`, `LiveClockClient` → `Services/`, `TreeSitterHighlighter` → `Services/Highlighting/`.
4. `git mv` `ClientsTestSupport` to `TestSupport/Fakes/`, and `AppFeature/Previews/PreviewClients.swift` with it. Move `NoSyntaxHighlighter` there too; it ships in the product today.
5. Repoint every feature target at `Core`, `DesignSystem` and `TestSupport` only. Delete the `Models`, `Clients` and `ClientsTestSupport` targets once nothing names them. `Syntax`, `Storage` and `Worktrees` go in Phases 3, 4 and 6.
6. Move `AppFeature` to `Sources/App/`, give it the `Services` dependency, and reduce the package to the single `AppFeature` product (D8). Update `project.yml` so the app target links only `AppFeature`, move the live-service construction from `HerderApp.init` into `AppEnvironment`, and run `just project`.
7. Add `scripts/check-boundaries.sh` (below) and `check` and `syntax` recipes to the `justfile`. `just syntax` already exists and already calls the crate's own build; don't reimplement it.

Steps 2 through 5 are mostly `git mv` plus import edits, but there are a lot of them. If it runs long, split after step 5: the module split is one PR, the `AppFeature` move (step 6) is another.

**Done when:** the app builds against `Core`, `Services` and `TestSupport`; `Models`, `Clients` and `ClientsTestSupport` are gone; and `just check` passes.

### `scripts/check-boundaries.sh`

Some checks are commented out until the phase that makes them pass. Enable each one in the task noted next to it.

```bash
#!/usr/bin/env bash
# Enforces the import rules from ARCHITECTURE.md that target dependencies can't.
set -euo pipefail
cd "$(dirname "$0")/.."   # always run from apps/herder

SRC="Packages/HerderKit/Sources"
APP_DIR="${APP_DIR:-Herder}"
RUST_MODULE="${RUST_MODULE:-HerderSyntaxFFI}"
fail=0

check() {  # usage: check "description" <rg args...>
  local desc="$1"; shift
  local hits
  hits=$(rg -l "$@" 2>/dev/null || true)
  if [[ -n "$hits" ]]; then
    echo "✗ $desc"
    echo "$hits" | sed 's/^/    /'
    fail=1
  fi
}

check "Core imports UI, persistence, or Rust" \
  -e "^import (SwiftUI|AppKit|SwiftData|$RUST_MODULE)" --type swift "$SRC/Core"

if [[ -d "$SRC/Features" ]]; then
  check "Feature imports Services or the Rust module" \
    -e "^import (Services|$RUST_MODULE)" --type swift "$SRC/Features"
fi

# No singletons. Passes today; keep it that way.
check "Singleton in HerderKit" \
  -e 'static (let|var) shared' --type swift "$SRC"

# Enable in Phase 6:
# check "Rust module imported outside Services" \
#   -e "^import $RUST_MODULE\$" --type swift --glob '!**/Services/**' "$SRC" "$APP_DIR"

# Enable in Phase 4, task 4e:
# check "SwiftData imported outside Services/Persistence" \
#   -e '^import SwiftData' --type swift --glob '!**/Services/Persistence/**' "$SRC" "$APP_DIR"

if [[ $fail -eq 0 ]]; then echo "✓ boundaries OK"; fi
exit $fail
```

The singleton check is enabled from the start, because the survey found nothing to fix.

---

## Phase 3: Service protocols

**Goal:** every external dependency sits behind a protocol in `Core`, with its implementation in `Services` and a fake in `TestSupport`.

Phase 2 did the moving. What's left is the gaps the survey found, one task each.

**Two of the five tasks moved to Phase 4.** `WorkspacesFeature` imports `Storage` in five files and passes the SwiftData `Workspace` objects themselves around — `@Query` in the view, `Workspace` as a parameter in `WorkspaceRow`, `WorkspaceSection` and `beginNewSession(in:)`. So `Storage` cannot become `Services/Persistence/` yet: a feature would then import `Services`, which is the one rule Phase 2 existed to make enforceable. Weaning the feature off SwiftData types is Phase 4a and 4e, and `RepositoryStore` and `WorkspaceAccess` go with it. `Storage` keeps its name and its place until then, which `Package.swift` and `AGENTS.md` both say at the target.

1. **Audit.** Done. Findings:
   - All seven protocols (`FileClient`, `GitClient`, `FileWatcherClient`, `BookmarkClient`, `FolderPickerClient`, `ClockClient`, `SyntaxHighlighter`) are `Sendable` and use Core types only.
   - **`*Client` stays.** The names are consistent and read fine, and renaming seven protocols, seven implementations, seven fakes and every call site buys no boundary that `Package.swift` isn't already enforcing. Substitute `*Client` wherever `ARCHITECTURE.md` says `*Service`.
   - **The `Live` prefix stays, and is now load-bearing.** It used to separate an implementation from its protocol inside one target; now it stops `Services.GitClient` colliding with `Core.GitClient` at every site that imports both.
   - **`BookmarkClient` is synchronous and does I/O**, which `ARCHITECTURE.md` says it shouldn't be: `makeBookmark` and `resolve` hit the disk, on the main actor. Making them `async` forces `WorkspaceStore.open()` async, which forces `AppEnvironment.start()` async, which changes how launch is sequenced — and Phase 4f rewrites launch sequencing anyway. Deferred to 4f deliberately, not overlooked.
   - **`FileWatcherClient.watch` is not `async`** and should not be: it returns an `AsyncStream`, so the suspension is in the iteration.
2. ~~**Split `Clients/Git`.**~~ Done in Phase 2. `GitStatus`, `GitChange`, `GitWorktreeStatus`, `GitWorktree`, `GitRepositoryKind` and `GitClientError` went to `Core/Models/`, and so did `GitRefName` and `GitWorktreeLocation`: they are pure string and URL arithmetic, and `NewSessionModel` needs them to refuse a branch name as it is typed, which a feature cannot do through `Services`.
3. ~~**`WorkspaceAccess`**~~ → Phase 4. It counts security-scoped folder access per `Workspace.id`, so it cannot be separated from the `Repository` rename, and an `actor` version of it pulls the same `async` cascade as `BookmarkClient`.
4. ~~**`RepositoryStore`**~~ → Phase 4a and 4e, for the reason above: the protocol has to return a Core value type, and that means the `Repository` rename and the `@Query` replacement happen together or not at all.
5. **Persistence.** Done. `StateStore` in `Core/Persistence/`, `SwiftDataStateStore` in `Storage/` — not `Services/Persistence/` yet — storing Codable snapshots as JSON blobs in a single new model:

```swift
@Model final class StoredState {
    @Attribute(.unique) var key: String
    var data: Data
    var updatedAt: Date
}
```

`StoredState` arrived as schema **V2**, with a `lightweight` migration stage from V1. V2 carries `Workspace` over rather than redeclaring it: a version that redeclares an unaltered model gives two classes one table. **The `Workspace` table is untouched**, which is the point — it holds the one thing in the app that cannot be rebuilt from disk (D6).

The blob approach is deliberate: it makes the Phase 7 swap to JSON files trivial, because the bytes in a row are already what a file would hold.

`SwiftDataStateStore` is an `actor` that makes a fresh `ModelContext` per call. A `ModelContext` is not `Sendable`, so it has to stay in one isolation domain; holding one would also be a second place keeping unsaved changes to a store the app's `mainContext` writes to.

`AppEnvironment` builds it and holds it as `state`. Nothing reads it until Phase 4 — built now so that the construction is proven before anything depends on it.

**Not in scope:** Process/PTY, Agents, Search and Settings services. Nothing in the app uses them yet, and a protocol with no caller and no implementation is a guess. They arrive with their features.

**Done when:** features and `AppFeature` touch the disk, processes, git and Rust only through protocols from `Core`. Still outstanding at the end of this phase: `WorkspacesFeature` reaches SwiftData through `Storage`. That is Phase 4's first job.

---

## Phase 4: Workspace state

The riskiest phase, because it changes the app's shape. Each sub-step is its own task and PR.

Scoped per D9: this moves the state that exists. `DocumentStore`, `AgentSessionStore`, tabs, dirty state and saving are **not** here — the editor is one read-only file and there is no agent runtime. They arrive with their features.

**4a. The rename. Done — but not behaviour-neutral, and that was the mistake.** Renaming the `@Model` class renamed the stored entity and stranded the existing store. Fixed by keeping the persisted class as `Workspace` with `Repository` as a typealias over it, and guarded by a committed V1 fixture in `StorageTests`. Full account in `realignment/notes.md`.
 `WorktreeState` → `Workspace` and `WorktreeStateStore` → `WorkspaceRegistry`, moved into `Core/Workspace/` with explicit `@MainActor`, since `Core` keeps the nonisolated default. The SwiftData `@Model Workspace` → `Repository`, and with it `WorkspaceStore` → `SwiftDataRepositoryStore` (named for its backing now, so `RepositoryStore` is free for the protocol in 4e), `WorkspaceStoreError` → `RepositoryStoreError`, `WorkspaceAccess` → `RepositoryAccess`. The `Worktrees` target is gone.

Three things deliberately *not* renamed:

- **`WorktreeStatus` and `GitWorktreeStatus`** keep their names. "Worktree" is git's word and these are git's view of one; `ARCHITECTURE.md` already keeps that vocabulary separate for `GitWorktree`.
- **`WorkspaceSchemaV1`, `WorkspaceSchemaV2`, `WorkspaceContainer`, `WorkspaceMigrationPlan`** keep theirs. They name the store as a whole rather than the model in it, they move to `Services/Persistence/` later in this phase, and Phase 7 deletes them. Renaming twice is waste.
- **`Workspaces.store` on disk must not be renamed at all.** The user's repository list lives in that file.

The feature's own types (`WorkspacesModel`, `AddWorkspaceModel`, `WorkspaceRow`) are the Repositories feature and get renamed in Phase 5, per D5.

`RepositoryStore` as a protocol is **not** here, for the reason Phase 3 found: it has to return a Core value type, so it cannot land before `@Query` goes. That is 4e.

**4b. Add the types, unused. Done.** In `Core/Workspace/`: `WorkspaceID`, `WorkspaceUIState`, `PersistedWorkspaceUIState`, `WorkspaceSnapshot`, `AppSnapshot`, plus `Workspace.uiState(_:)`, `.snapshot` and `.restore(from:)`. 19 tests.

Restoring turned out to belong on first ask rather than at launch: `restore(from:)` parks the blobs and `uiState(_:)` fills the instance when a feature asks for it. That is what lets a workspace restore state for types `Core` has never heard of, and it means state for a pane the user never opens is passed through untouched instead of being dropped.

Two things from this step's original list are **not** here:

- **`WorkspaceRegistry.open(_:)` and `close(_:)`.** The registry has `select(_:)`, which holds one workspace and stops the rest. Adding open and close beside it would be two ways to say one thing and two places for the set of live workspaces to disagree — exactly what this phase's own rule warns about. They replace `select` in 4g, where the single-workspace behaviour changes anyway.
- **`WorkspaceServicesFactory`.** Workspace-scoped services are the four clients the registry already threads through. A factory for them would be a wrapper with nothing to wrap until search or a PTY exists.

**4c. Per-window active workspace. Done.**

`WindowModel` in `Sources/App/` owns `activeWorkspaceID`. The root view resolves the workspace from the id and injects it with `.environment(workspace)`; switching sets the id and nothing else.

This was not the "establish a path" the step first described. The fact it is about was **already owned by a feature**: `WorkspacesModel` held `selectedWorktree` and `selectedWorkspace` and persisted both to `UserDefaults`, which meant every window in the app necessarily agreed about which checkout was showing. So it was a move of ownership, and per D12 it needed a way for a feature to reach a window it cannot import:

- **Reading:** `WorkspaceSection` takes `@Environment(Workspace.self)` and marks the row whose path matches. Nothing asks which workspace is active.
- **Writing:** a tap calls `openWorkspace(WorkspaceID(…))`, an `OpenWorkspaceAction` the App target supplies.
- **Restoring:** `@SceneStorage("activeWorkspacePath")` in `AppView`, per window, replacing the two global `UserDefaults` keys. `ARCHITECTURE.md` already specified `@SceneStorage` for this, so 4f inherits it rather than adding it.
- **Deselecting:** `AppView` watches the active workspace's `isAvailable`, which goes false when its folder vanishes. The old check lived in `WorkspacesModel.refresh`, comparing git's worktree list against the selection; the watcher knows sooner and in one place.
- `WorkspacesModel` keeps the association the selection used to track by hand, now derived from the listings it already had: `nameOfWorkspace(holding:)` and `isKnown(_:)`.

**4d. Move feature UI state onto the workspace. Partly done.**

The original list was wrong about two of its three items, because not all of this state is per-workspace:

| State | Scope | Where it goes |
|---|---|---|
| the file tree's `expanded` | **per workspace** — the user opened folders in *this* checkout | `WorkspaceUIState`. **Done:** `ExplorerUIState`. |
| `RepositoriesModel.selectedWorktree` | **per window** — it *is* "which workspace is active" | `WindowModel`, in 4c. It cannot be per-workspace state: a workspace cannot hold which workspace is active. |
| `RepositoriesModel.collapsed` | **app-wide** — which repositories are folded in the sidebar, and the sidebar is app-scoped (D5) | `AppSnapshot`, in 4f. Not `WorkspaceUIState`. |

Still to do here: the editor's open file, once there is more than one.

`UserDefaults.standard` leaves the feature when the last two land, not with this step.

Repoint every reader and delete the old holder **in the same task** — never merge with two sources of truth for the same fact.

**4e. Persistence off `@Query`. Done.**

`Repository` is a Core value type, held by `RepositoryStore` — an `@Observable` store in `Core/Repositories/` — and persisted in `AppSnapshot` through `StateStore`. The sidebar reads `store.repositories` and Observation redraws it, which is what replaced `@Query`'s no-round-trip immediacy: the old design got that by writing through the same `mainContext` the view read, and owning the array gives it without a feature knowing what a `ModelContext` is.

The rows came across rather than being abandoned (D6). `LegacyRepositoryImport` copies them into the snapshot once, guarded on the new list being empty — so a user who has deleted every repository since migrating does not get them all back, and SwiftData is not touched at all on any launch after the first. **The `ZWORKSPACE` table is left exactly as it was.**

Then `Storage` finally became `Services/Persistence/`, which Phase 3 could not do: the feature had been passing `@Model` objects around, and that was the whole blocker.

**All four boundary checks now pass**, including "SwiftData imported outside Services/Persistence". Getting there needed one more seam: `AppEnvironment` was holding a `ModelContainer`, so the App target still imported SwiftData. `PersistenceStack` in `Services/Persistence/` now hands back a `StateStore` and a list of `Repository` values and keeps the container to itself — which is also what makes the Phase 7 swap a replacement of one type rather than a change to the composition root.

Verified against the real store: the `herder` row arrived in the snapshot with its 740-byte bookmark, its path and its order, and a second launch neither re-imported nor duplicated it.

**4f. Restoration. Done, bar the part that needs 4g.**

`@SceneStorage` for `activeWorkspaceID` landed in 4c. What this step added is the writing and reading back of everything else:

- **Sidebar collapse is on the repository record**, as `Repository.isCollapsed`, beside `order` and for the same reason: it is the user's arrangement of this repository, there is one sidebar, and it is worth keeping. That retires **the last `UserDefaults` key in the package** — `grep UserDefaults Sources/` now finds only a comment explaining what used to be there.
- **`Workspace` writes its own snapshot**, debounced about 400ms after UI state settles, and the registry writes it before letting a workspace go. Restoring happens in `select`, before the caller is handed the workspace, so a feature asking for its UI state finds the last run's already in it.
- **`willTerminate` still hands back security-scoped access**, and still cannot save: it is a synchronous callback with nowhere to await. That is why the debounce is short rather than the ARCHITECTURE-suggested second, and why `stop()` is deliberately not `async`. Closing the remaining few-hundred-millisecond gap means `applicationShouldTerminate` returning `.terminateLater`, which is its own task.

**Not done:** restoring *several* open workspaces from `AppSnapshot.openWorkspaces`. The registry holds one at a time, so there is nothing to restore beyond the active one, which `@SceneStorage` already does. It moves to 4g, with the change that makes several possible.

Verified against the real store: `herder` carries `isCollapsed`, and switching between `main` and `feat/test` left a snapshot apiece under its own key.

**4g. Several live workspaces at once.** The one deliberate behavior change in this phase, so it goes last and alone. `WorkspaceRegistry.select` today **stops** every worktree but the selected one, keeping only the watcher position; the target architecture wants background workspaces to keep running. Each live workspace costs a watcher and a git status call, which is why `WorktreeStateStore`'s own doc comment calls widening it "a deliberate step and not a side effect". Confirm with tests that a background workspace's listings and git state survive a switch.

**Gate:** Kurt runs the full smoke test before Phase 5 starts.

---

## Phase 5: Feature extraction (parallel)

One task per feature, each in its own worktree. Phase 2 already moved the shared code out from under them, so this is mostly renaming folders to the convention, tightening public surface, and resolving whatever coupling is left.

Order if running serially: Repositories, FileTree, Editor.

**For each feature:**

1. Rename its folder to the convention: `Sources/Features/<Name>/`, not `<Name>Feature/`. Update its `path:` in `Package.swift` and its test target's.
2. Fix compile errors. Each error that crosses the new boundary is a coupling to resolve:
   - It reaches into another feature → go through `Workspace`, or move the shared piece to `Core` or a component module.
   - It uses a concrete service → use the protocol from `Core`.
   - It uses SwiftData or `HerderSyntaxFFI` types → these should be gone after Phases 3 and 4. If not, stop and ask.
3. Expose a small public entry point (usually one view, like `FileTreePanel`). Keep everything else `internal`.
4. Make previews work with fakes from `TestSupport`.
5. Add tests for the feature model.

**Per-feature specifics:**

- **Repositories** (`WorkspacesFeature` today, 1,355 lines). Rename the module, folder and types per D4 and D5: `WorkspacesModel` → `RepositoriesModel`, `WorkspacesView` → `RepositoriesView`, `AddWorkspaceModel`/`Overlay` → `AddRepositoryModel`/`Overlay`. It keeps `NewSessionModel`. App-scoped: it takes the `WorkspaceRegistry`, not a `Workspace`.
- **FileTree** (`ExplorerFeature` today). Rename per D3, types included.
- **Editor**. Largest surface per file but least coupled. `SyntaxAttributes` is the one place kinds meet colours and stays here by design.
- **AppFeature** is not a feature and is not extracted. It moved in Phase 2 step 6.

Don't change editor rendering (for example moving highlighting to `NSTextLayoutManager` rendering attributes) in this phase. `ARCHITECTURE.md` asks for it, but it is a behavior change; log it in `notes.md` as a follow-up.

The four features in `ARCHITECTURE.md`'s list that don't exist — `AgentSessions`, `Terminal`, `Search`, `CommandPalette`, `Settings` — and the `TerminalUI` component are **not** created here. Nothing would be in them.

**Done when:** all feature code lives in feature targets following the naming convention, and `AppFeature` contains only composition, windows and commands.

---

## Phase 6: Syntax highlighter boundary (parallel with Phase 5)

The highlighter stays in `packages/syntax-highlighter`. This phase changes how Swift consumes it, not the highlighter itself. Most of it is already true — the survey found exactly one Swift file importing `HerderSyntaxFFI` — so this is mainly finishing the split Phase 2 started and locking it in.

1. Confirm the only Swift code importing `HerderSyntaxFFI` is `Services/Highlighting/`. Everything else goes through the `SyntaxHighlighter` protocol in `Core`.
2. Confirm no FFI type (`HdrToken`, `HDR_LANGUAGE_NONE`) appears in `Core`, a feature, or `AppFeature`. The `HdrToken` → `SyntaxToken` conversion stays in `Services/Highlighting/`.
3. **Offsets: nothing to do.** The crate already converts UTF-8 byte offsets to UTF-16 before handing tokens over, so there is no conversion on the Swift side and there must not be a second one. Recorded in `ARCHITECTURE.md` and the survey, §7.
4. Delete the `Syntax` target once it is empty.
5. Uncomment the "Rust module imported outside Services" check in `check-boundaries.sh`.
6. If any of this needs a change inside `packages/syntax-highlighter`, stop and ask. It becomes its own task.

**Done when:** the highlighter's tests pass, `just check` passes with the Rust-module check enabled, and the app highlights as before.

---

## Phase 7: Persistence swap (optional, ask Kurt first)

1. Decide where the security-scoped bookmark lives: base64 in JSON, the Keychain, or SwiftData kept for just this (D6). `ARCHITECTURE.md` says secrets go in the Keychain; a bookmark is a capability rather than a secret, so this is a real decision.
2. Implement `FileStateStore` (JSON, atomic writes, debounced) behind `StateStore`, using the layout in `ARCHITECTURE.md`.
3. Swap it in `AppEnvironment`.
4. **Migrate the repository list.** Not a fresh start: the bookmarks, names and order are the user's work and can't be regenerated (D6).
5. Delete `SwiftDataStateStore`, `StoredState` and the container, and remove SwiftData from the project.

---

## Phase 8: Cleanup

1. Delete dead code and empty folders.
2. Add a `// CONCURRENCY:` comment to each escape hatch and each remaining `DispatchQueue` use, or remove it. The survey lists all five.
3. Gitignore the `default.profraw` droppings.
4. Run `scripts/check-boundaries.sh` in a pre-commit hook. There is no CI in this repo to add a job to.
5. Update `ARCHITECTURE.md` and `AGENTS.md` with anything learned along the way.
6. Ask about the root `README.md`, which describes the old structure and is outside `apps/herder/`.
7. Move this file and `docs/realignment/` to `docs/archive/`.

---

## Handing a task to an agent

```
You're working on Herder, a native macOS code editor and agent runner
(Swift 6, SwiftUI, Rust). It lives at apps/herder/ in a monorepo; work
from that folder and don't change anything outside it.

Read these in full before doing anything:
- apps/herder/docs/ARCHITECTURE.md
- apps/herder/docs/REALIGNMENT.md  (especially the Decisions section)
- apps/herder/docs/realignment/survey.md

Your task: Phase <N>, <task name>.
<specifics: which feature or service, relevant files from the survey>

Follow the rules of engagement and the definition of done in REALIGNMENT.md.
Work on branch realign/p<N>-<slug>. If you hit any "stop and ask" condition,
stop and explain what you found instead of guessing.

When you're done, update the progress checklist and summarize anything you
added to docs/realignment/notes.md.
```

---

## Progress

- [x] **P0** Survey
- [x] **P1** Swift 6 language mode *(already done; nothing to change)*
- [x] **P2** Core, Services, TestSupport, boundary script, `AppFeature` move
  - [x] 2a module split: `Core`, `Services`, `TestSupport`, boundary script, `just check`
  - [x] 2b `AppFeature` → `Sources/App/`, single product, `AppEnvironment`
- [x] **P3** Service protocols *(two tasks moved to P4; see the phase)*
  - [ ] Audit the seven existing protocols
  - [ ] Split `Clients/Git` into values and parsers
  - [ ] `WorkspaceAccess` behind a protocol
  - [ ] `RepositoryStore`
  - [ ] `StateStore` (SwiftData-backed)
- [ ] **P4** Workspace state *(gate: smoke test)*
  - [x] 4a rename to `Workspace` / `WorkspaceRegistry` / `Repository`
  - [x] 4a′ `RepositoryStore` owns the list; `RepositoryAccess` moved to `Core`
  - [x] 4b snapshot and UI-state types + tests
  - [x] 4c `WindowModel` and per-window active workspace
  - [~] 4d feature UI state onto the workspace
    - [x] file tree expansion → `ExplorerUIState`
    - [x] sidebar collapse → `Repository.isCollapsed` *(4f)*
    - [x] repository list → `AppSnapshot` *(4e)*
  - [x] 4e persistence off `@Query`, `Storage` → `Services/Persistence/`
  - [x] 4f restoration *(`openWorkspaces` moved to 4g)*
  - [ ] 4g several live workspaces at once, and restoring them from `AppSnapshot`
- [ ] **P5** Features
  - [ ] Repositories
  - [ ] FileTree
  - [ ] Editor
- [ ] **P6** Syntax highlighter boundary
- [ ] **P7** Persistence swap *(optional)*
- [ ] **P8** Cleanup
