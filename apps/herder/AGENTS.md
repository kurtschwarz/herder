# Herder (macOS app)

**`docs/ARCHITECTURE.md` is the rulebook.** Read it before changing anything. It
owns the layering, the dependency rules, the state model, the concurrency rules
and the conventions. This file holds only the lookup table for where a new file
goes, and it does not repeat what is in there.

The codebase is mid-realignment: `docs/REALIGNMENT.md` describes the move from the
structure that is to the structure that should be, `docs/realignment/survey.md`
maps what was found, and the Decisions section of the plan records the calls that
have been made. If this file and `ARCHITECTURE.md` disagree, `ARCHITECTURE.md`
wins and this file is stale — say so.

A near-empty app target plus a local Swift package holding every line of real
code, organised by feature rather than by type. `../../README.md` carries the
rationale.

## Where a new file goes

| Adding | Goes in |
| --- | --- |
| A plain value type | `Core/Models/`, one type per file named after the type |
| A protocol for anything touching disk, network, processes or the clock | `Core/Services/` |
| Pure logic about an external system, with no I/O | `Core/Models/` — see `GitRefName` |
| The live implementation of such a protocol | `Services/<Area>/` |
| A fake for that protocol | `TestSupport/Fakes/`, wrapped in `#if DEBUG` |
| A user-facing feature | its own target under `Sources/Features/<Name>/`, module `<Name>Feature` |
| A subview used by one feature | that feature's `Components/` |
| AppKit bridging | that feature's `Platform/` |
| A view, modifier or shape used by two features | `DesignSystem/Views`, `/Modifiers`, `/Shapes` |
| A design token | `DesignSystem/Theme.swift` |
| A colour for a token kind | `DesignSystem/Theme.swift`, paired in `EditorFeature/Platform/SyntaxAttributes.swift` |
| Anything that constructs a concrete service | `AppFeature` — nowhere else |
| Something the app persists about itself | nothing — encode it to a snapshot and put it through `StateStore`. No schema version, no migration. |
| A new SwiftData model (rare; prefer the above) | `Storage/`, in a new `WorkspaceSchemaV<n>` with a migration stage |
| Live state two features both read | `Worktrees/` for now, not whichever feature needed it first. Becomes `Core/Workspace/` in Phase 4. |
| A language for the editor to highlight | `../../packages/syntax-highlighter`, not here. See its `AGENTS.md`. |

Organise by feature, not by type: a feature's view, model and subviews sit together.
Name files after the single type they hold.

A new feature target needs `path: "Sources/Features/<Name>"` and its test target
`path: "Tests/Features/<Name>FeatureTests"`. SwiftPM looks directly under
`Sources` and `Tests` by default, so without those the build cannot find the files.

## Not yet moved

Two modules still sit outside the target layout, and `Package.swift` says so at
each one. Don't file new code in them without reading the plan:

- **`Storage/`** — SwiftData models, schema, container, and `SwiftDataStateStore`.
  Goes to `Services/Persistence/` in Phase 4, once `WorkspacesFeature` stops
  passing `@Model` objects around and can drop `import Storage`. Until then a
  feature still reaches SwiftData through it, which is why the boundary check
  for that is the one still commented out.
- **`Worktrees/`** — `WorktreeState` and `WorktreeStateStore`. Become `Workspace`
  and `WorkspaceRegistry` in `Core/Workspace/` in Phase 4.

`AppFeature` sits at `Sources/App/`, outside `Sources/Features/`, because it is
the composition root rather than a feature. `AppEnvironment` there is the only
place in the codebase that names a concrete service type, and the one HerderKit
module that may import `Services`. Keep `Herder/` to scenes alone.

## Commands

Run from this directory, or append `apps/herder` to the root `justfile` equivalents.
`ARCHITECTURE.md` lists them all; these are the ones used most.

```sh
just test          # Swift Testing suites via xcodebuild, no app host
just build         # regenerates the project, then builds
just check         # the import rules the compiler cannot enforce
just dev           # build and run with output in the terminal
just syntax        # rebuild the Rust crate and refresh its XCFramework
```

`Herder.xcodeproj` is generated and gitignored. Files under `HerderKit` are picked
up by SwiftPM, so only changes to `Herder/` or `UITests/` need `just project`.

`HerderKit` has a `.binaryTarget` on `Vendor/HerderSyntaxFFI.xcframework`, built
from `../../packages/syntax-highlighter` and gitignored like the project file.
`test`, `build` and `bootstrap` all depend on the `syntax` recipe, so it is never
stale; a fresh clone needs `just bootstrap` before SwiftPM will resolve the
package, and needs a Rust toolchain for that to work.
