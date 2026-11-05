# Herder Re-alignment Plan

**Goal:** move the existing Herder codebase to the architecture in `docs/ARCHITECTURE.md` incrementally. This is not a rewrite. The app keeps building and working after every task.

Read `ARCHITECTURE.md` before this file. It describes where we're going; this file describes how we get there.

Herder lives at `apps/herder/` in a monorepo. Paths here follow the same convention as `ARCHITECTURE.md`: relative to `apps/herder/`, except paths starting with `packages/`, which are relative to the repo root. Run commands from `apps/herder/`.

## Rules of engagement

1. Read `docs/ARCHITECTURE.md` and `docs/realignment/survey.md` (once it exists) in full before starting any task.
2. One task at a time, on its own branch: `realign/p<N>-<slug>` (for example `realign/p5-filetree`).
3. **Move first, change later.** A task that moves code must not change behavior. If you spot a bug or a better design while moving, write it in `docs/realignment/notes.md` and keep going.
4. Every task ends green. See "Definition of done".
5. Keep diffs reviewable. If a task grows past roughly 1,500 changed lines (not counting pure file moves), stop and propose a split.
6. Use `git mv` for moves so history follows the files.
7. Never delete user data, SwiftData stores, or files outside the repo.
8. Update the progress checklist at the bottom of this file in the same PR.
9. Commit messages: `realign(p<N>): <what changed>`.
10. **Leave `packages/syntax-highlighter` where it is.** Don't move, rename, or restructure it. Tasks in this plan only change how Swift consumes it.
11. **Stay inside `apps/herder/`.** The only thing outside it you may read is `packages/syntax-highlighter`, and you don't change it. Don't touch other apps, other packages, or repo-root config (root CI, workspace files, root `justfile`). If a task seems to need that, stop and ask.

## Stop and ask Kurt when

- The survey contradicts an assumption in this plan or in `ARCHITECTURE.md`.
- A change would alter user-visible behavior.
- A SwiftData model holds data that can't be recreated from disk or git (for example user-written prompts or notes).
- You need concurrency escape hatches (`@unchecked Sendable`, `nonisolated(unsafe)`) in more than a couple of places within one task.
- Two features turn out to be genuinely coupled and would need merging or redesigning.
- Something in `ARCHITECTURE.md` looks wrong for this codebase.
- A task seems to need changes inside `packages/syntax-highlighter`, especially to its public API.
- A task seems to need changes anywhere outside `apps/herder/`.

## Definition of done (every task)

- [ ] The app builds: `xcodebuild -scheme Herder -destination 'platform=macOS' build`
- [ ] Swift tests pass: `swift test --package-path HerderKit` (run `just rust` first if the highlighter build is stale)
- [ ] Rust tests pass: `cargo test` in `packages/syntax-highlighter` (exact command from the survey)
- [ ] `scripts/check-boundaries.sh` passes (from Phase 2 on)
- [ ] No new concurrency warnings
- [ ] Progress checklist updated
- [ ] PR description lists anything added to `docs/realignment/notes.md`

Before Phase 2 sets up the `justfile`, use whatever commands the survey records.

## Manual smoke test (Kurt runs this at review gates)

1. Launch the app and open a folder.
2. Open a few files. Syntax highlighting appears. Edit and save.
3. Start an agent session. It runs and responds.
4. Open a second worktree of the same repo. Switch back and forth. The agent in the first worktree keeps running, and tabs and scroll positions restore when you switch back. *(after Phase 4)*
5. Quit and relaunch. Workspaces, tabs, and each window's workspace restore. *(after Phase 4)*

## Parallelization

```
P0 → P1 → P2 → P3 → P4 ─┬─► P5  one agent per feature, in parallel worktrees
                        ├─► P6  parallel with P5 (highlighter boundary)
                        └─► P7  any time after P4 (optional)
                                      └─► P8 after everything else
```

Phases 0 through 4 are sequential, because each one reshapes code the next one depends on. From Phase 5 on, run agents in separate worktrees. `Package.swift` is the merge hotspot: each agent adds only its own target entry and rebases before opening a PR.

---

## Phase 0: Survey (read-only)

**Goal:** a factual map of the current code so later phases aren't guessing. No code changes in this phase.

**Output:** `docs/realignment/survey.md` covering:

1. **Targets and packages:** every Xcode target and SwiftPM package under `apps/herder/`, what's in it, and what it depends on. Also note anything at the repo root that Herder relies on (root build tooling, CI jobs, shared config), and the real name of the app target's source folder (`App/` in these docs).
2. **Commands:** how to build, test, and run today, including how Rust gets built.
3. **Concurrency status:** Swift language mode and strict concurrency setting per target. On a throwaway branch, switch to Swift 6 mode and record the error and warning counts per target.
4. **SwiftData inventory:** every `@Model` type (fields and relationships), every `@Query`, and every use of `ModelContext`, `modelContainer`, or `modelContext`, grouped by file. For each model, note whether its data can be recreated from disk or git.
5. **Global and shared state:** singletons (`static let shared`, `static var`), `@EnvironmentObject`, `@AppStorage`, `@StateObject` at the app root, and `NotificationCenter` used to carry app state.
6. **External dependencies:** every place the app touches the disk, git, processes/PTYs, the network, or Rust directly. This becomes the Phase 3 service list.
7. **Syntax highlighter (`packages/syntax-highlighter`):** its internal layout, how it's built, how Swift bindings are generated (UniFFI, cbindgen, hand-written, ...), where the build output lands, whether it already ships a `Package.swift` (and its product name), how the app currently links it, the public API Swift sees, and every Swift file that uses its types directly.
8. **Feature inventory:** a table mapping existing files and folders to their target home (`EditorFeature`, `FileTreeFeature`, `AgentSessionsFeature`, `TerminalFeature`, `SearchFeature`, `CommandPaletteFeature`, `SettingsFeature`, `TerminalUI`, `Core`, `Services`, `DesignSystem`, `App`, or `unclear`).
9. **Cross-feature coupling:** places where one feature's code directly references another feature's types.
10. **Open questions:** anything that doesn't fit the target architecture and needs a decision.

**Useful searches:**

```bash
rg -n '@Model|@Query|ModelContext|modelContainer|modelContext' --type swift
rg -n 'static (let|var) shared|@EnvironmentObject|@AppStorage|@StateObject' --type swift
rg -n 'FileManager|Process\(|posix_spawn|forkpty|URLSession' --type swift
rg -n 'DispatchQueue|@unchecked Sendable|nonisolated\(unsafe\)|@preconcurrency' --type swift
rg --no-filename '^import ' --type swift | sort | uniq -c | sort -rn
```

**Gate:** Kurt reviews the survey before Phase 1 starts.

---

## Phase 1: Swift 6 language mode

Skip this phase if the survey shows every target already in Swift 6 mode with zero concurrency warnings.

**Steps:** convert one target at a time, starting with leaf targets. Set Swift 6 mode, then fix errors. When choosing fixes, prefer them in this order:

1. Make value types `Sendable` (usually free).
2. Put UI types on the main actor.
3. Turn shared mutable classes into actors.
4. Replace `DispatchQueue` and completion handlers with `async`/`await` where you're already touching the call site.
5. Use escape hatches last, each with a `// CONCURRENCY:` comment.

Don't restructure modules in this phase.

**Done when:** every target is in Swift 6 mode with zero concurrency warnings.

---

## Phase 2: Package skeleton and Core

**Goal:** `HerderKit` exists with the target layout, pure model types live in `Core`, and boundary checks run.

**Steps:**

1. Create `HerderKit/Package.swift` from the template in `ARCHITECTURE.md`, with these targets only for now: `Core`, `Services`, `DesignSystem`, `TestSupport`, and the test targets. Feature targets get added in Phase 5. Hook up `packages/syntax-highlighter` whichever way the survey says fits: as a package dependency if it ships a `Package.swift`, or as a `binaryTarget` plus thin `RustBridge` target if it doesn't. Don't change anything inside the highlighter to make this work; if it can't be consumed as-is, stop and ask.
2. Add the package to the Xcode project and link it from the app target.
3. `git mv` pure value types (no UI, no I/O, no SwiftData) into `Core/Models/`. Make them `public` and `Sendable` as needed. **Do not move `@Model` types.**
4. Add `scripts/check-boundaries.sh` (below) and a `justfile` with `rust`, `test`, and `check` recipes if the repo doesn't have equivalents. `just rust` calls the highlighter's existing build; it doesn't reimplement it.

**Done when:** the app builds using Core types from the package, and the boundary script passes.

### `scripts/check-boundaries.sh`

Some checks are commented out until the phase that makes them pass. Enable each one in the task noted next to it.

```bash
#!/usr/bin/env bash
# Enforces the import rules from ARCHITECTURE.md that target dependencies can't.
set -euo pipefail
cd "$(dirname "$0")/.."   # always run from apps/herder

SRC="HerderKit/Sources"
APP_DIR="${APP_DIR:-App}"            # set to the app target's folder from the survey
RUST_MODULE="${RUST_MODULE:-RustBridge}"  # set to the highlighter's Swift module name from the survey
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

# Enable in Phase 6 (the app may still import the highlighter directly until then):
# check "Rust module imported outside Services" \
#   -e "^import $RUST_MODULE\$" --type swift --glob '!**/Services/**' --glob '!**/RustBridge/**' "$SRC" "$APP_DIR"

# Enable at the end of Phase 3:
# check "Singleton in HerderKit" \
#   -e 'static (let|var) shared' --type swift "$SRC"

# Enable in Phase 4, task 4d:
# check "SwiftData imported outside Services/Persistence" \
#   -e '^import SwiftData' --type swift --glob '!**/Services/Persistence/**' "$SRC" "$APP_DIR"

if [[ $fail -eq 0 ]]; then echo "✓ boundaries OK"; fi
exit $fail
```

---

## Phase 3: Service protocols

**Goal:** every external dependency from survey item 6 sits behind a protocol in `Core`, with its implementation in `Services` and a fake in `TestSupport`.

**One service per task.** For each:

1. Define the protocol in `Core/Services/<Name>.swift`. It uses Core types only, is `Sendable`, and is `async` wherever it does I/O.
2. `git mv` the existing implementation into `Services/<Area>/` and conform it to the protocol. Change as little as possible inside it.
3. Write `TestSupport/Fakes/Fake<Name>.swift`.
4. Construct the real implementation in `App/AppEnvironment.swift` and pass it to consumers through `init` or an `@Entry` environment value. Remove singleton access as you go.

### Persistence (its own task)

1. Define `StateStore` in `Core/Persistence/`.
2. Implement `SwiftDataStateStore` in `Services/Persistence/`, storing Codable snapshots as JSON blobs in a single new model:

```swift
@Model final class StoredState {
    @Attribute(.unique) var key: String
    var data: Data
    var updatedAt: Date
}
```

3. Add `StoredState` to the existing container's schema. **Leave the existing `@Model` types alone.** Views keep using them until Phase 4.

The blob approach is deliberate: it makes the Phase 7 swap to JSON files trivial.

**Done when:** features and the app touch the disk, processes, git, and Rust only through protocols. Enable the singleton check in `check-boundaries.sh`.

---

## Phase 4: Workspace state

This is the riskiest phase, because it changes the app's shape. Each sub-step is its own task and PR.

**4a. Add the types, unused.** In `Core/Workspace/`: `WorkspaceID`, `Workspace`, `WorkspaceRegistry`, `DocumentStore`, `AgentSessionStore`, `WorkspaceUIState`, `PersistedWorkspaceUIState`, `AppSnapshot`, `WorkspaceSnapshot`, and the `WorkspaceServicesFactory` protocol (implementation in `Services/Workspace/`). Write tests for the registry's open, close, and switch behavior using fakes.

**4b. Wire it in alongside the existing state.** `AppEnvironment` creates the registry. Add `WindowModel` with `activeWorkspaceID`. The root view resolves the active workspace and injects it with `.environment(workspace)`. The existing state still drives the UI.

**4c. Move state into `Workspace`, one domain per task:**
- open documents and tabs → `DocumentStore`
- agent sessions → `AgentSessionStore`
- git branch and status → `Workspace`
- feature UI state that must survive a switch → `WorkspaceUIState` types

For each domain, repoint every reader and delete the old holder **in the same task**. Never merge with two sources of truth for the same fact.

**4d. Move persistence off `@Query`.** Replace `@Query` and `ModelContext` use in views and models with reads from `Workspace`, plus snapshot save and restore through `StateStore`. Delete the old `@Model` types once nothing reads them (stop and ask first if any hold irreplaceable data). Enable the SwiftData check in `check-boundaries.sh`.

**4e. Restoration.** Store `activeWorkspaceID` per window with `@SceneStorage`. On launch, the registry restores open workspaces from `AppSnapshot`.

**4f. Worktree switching.** Switching sets `activeWorkspaceID` and nothing else. Confirm with tests that agent sessions and documents in background workspaces survive a switch.

**Gate:** Kurt runs the full smoke test before Phase 5 starts.

---

## Phase 5: Feature extraction (parallel)

One task per feature, each in its own worktree. If running serially, go in this order: Settings, CommandPalette, Search, FileTree, TerminalUI + Terminal, AgentSessions, Editor. Editor goes last because it's the largest; split it into sub-tasks (text view, gutter, tabs) if it's big.

`TerminalUI` is a component module, not a feature. Extract it in the same task as `TerminalFeature`, before `AgentSessionsFeature` starts.

**For each feature:**

1. Add its target to `Package.swift` with the `feature(...)` helper from the template.
2. `git mv` the feature's files according to the survey's feature inventory.
3. Fix compile errors. Each error that crosses the new boundary is a coupling to resolve:
   - It reaches into another feature → go through `Workspace`, or move the shared piece to `Core` or a component module.
   - It uses a concrete service → use the protocol from `Core`.
   - It uses SwiftData or syntax-highlighter types → these should be gone after Phases 3 and 4. If not, stop and ask.
4. Expose a small public entry point (usually one view, like `FileTreePanel`). Keep everything else `internal`.
5. Make previews work with fakes from `TestSupport`.
6. Add tests for the feature model.

Don't change editor rendering (for example moving highlighting to rendering attributes) in this phase. That's a behavior change; log it in `notes.md` as a follow-up.

**Done when:** all feature code lives in feature targets, and the app target contains only composition, windows, and commands.

---

## Phase 6: Syntax highlighter boundary (parallel with Phase 5)

The highlighter stays in `packages/syntax-highlighter`. This phase changes how Swift consumes it, not the highlighter itself.

1. Make sure the only Swift code that imports the highlighter's module is `Services/Highlighting/` (plus the thin `RustBridge` target, if one was needed in Phase 2). Everything else goes through the `HighlightService` protocol from Phase 3.
2. Convert the highlighter's types to Core types (`HighlightSpan`, `TextEdit`, ...) inside the highlighting service. No highlighter types in Core, features, or the app.
3. Put UTF-8 ↔ UTF-16 offset conversion in exactly one place, inside that service, unless the highlighter already speaks UTF-16. Record which in `notes.md`.
4. Wire `just rust` and `just test` to the highlighter's existing build and test commands.
5. Uncomment the "Rust module imported outside Services" check in `check-boundaries.sh`.
6. If any of this needs a change inside `packages/syntax-highlighter` (a new API, different output types), stop and ask. It becomes its own task.

**Done when:** the highlighter's tests pass, `check-boundaries.sh` passes with the "Rust module imported outside Services" check, and the app highlights as before.

---

## Phase 7: Persistence swap (optional, ask Kurt first)

1. Implement `FileStateStore` (JSON, atomic writes, debounced) behind `StateStore`, using the layout in `ARCHITECTURE.md`.
2. Swap it in `AppEnvironment`.
3. Delete `SwiftDataStateStore` and `StoredState`, and remove SwiftData from the project.

No data migration is needed while Herder is unshipped (confirm with Kurt first). The first launch after the swap starts fresh.

---

## Phase 8: Cleanup

1. Delete dead code and empty folders.
2. Grep for concurrency escape hatches. Justify each one with a `// CONCURRENCY:` comment, or remove it.
3. Run `scripts/check-boundaries.sh` in CI or a pre-commit hook.
4. Update `ARCHITECTURE.md` with anything learned along the way.
5. Move this file and `docs/realignment/` to `docs/archive/`.

---

## Handing a task to an agent

```
You're working on Herder, a native macOS code editor and agent runner
(Swift 6, SwiftUI, Rust). It lives at apps/herder/ in a monorepo; work
from that folder and don't change anything outside it.

Read these in full before doing anything:
- apps/herder/docs/ARCHITECTURE.md
- apps/herder/docs/REALIGNMENT.md
- apps/herder/docs/realignment/survey.md (if it exists)

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

- [ ] **P0** Survey *(gate: Kurt reviews)*
- [ ] **P1** Swift 6 language mode
- [ ] **P2** Package skeleton, Core, boundary script, justfile
- [ ] **P3** Service protocols
  - [ ] FileSystem
  - [ ] Git
  - [ ] Process / PTY
  - [ ] Highlighting
  - [ ] Search
  - [ ] StateStore (SwiftData-backed)
  - [ ] Settings
  - [ ] *(others from the survey)*
- [ ] **P4** Workspace state *(gate: smoke test)*
  - [ ] 4a types + tests
  - [ ] 4b wiring
  - [ ] 4c documents
  - [ ] 4c agent sessions
  - [ ] 4c git state
  - [ ] 4c UI state
  - [ ] 4d persistence off `@Query`
  - [ ] 4e restoration
  - [ ] 4f worktree switching
- [ ] **P5** Features
  - [ ] Settings
  - [ ] CommandPalette
  - [ ] Search
  - [ ] FileTree
  - [ ] TerminalUI + Terminal
  - [ ] AgentSessions
  - [ ] Editor
- [ ] **P6** Syntax highlighter boundary
- [ ] **P7** Persistence swap *(optional)*
- [ ] **P8** Cleanup
