# Herder (macOS app)

Structure follows Apple's SwiftUI sample-project guidance: a near-empty app target
plus a local Swift package holding every line of real code, organised by feature
rather than by type. `../../README.md` carries the rationale; this file is the rules.

## Layout

```
apps/herder/
├── project.yml               # source of truth for the generated Herder.xcodeproj
├── Herder/                   # app target: @main, Info.plist, entitlements, assets
├── UITests/                  # XCTest only; Swift Testing has no UI automation
└── Packages/HerderKit/
    ├── Package.swift
    ├── Sources/
    │   ├── Features/         # one target per feature, each with an explicit path
    │   │   ├── WorkspacesFeature/  # workspace list, worktrees, add modal
    │   │   ├── ExplorerFeature/    # file tree of the selected worktree
    │   │   ├── EditorFeature/      # read-only view of the file clicked in the explorer
    │   │   └── AppFeature/   # root view and composition
    │   │       ├── AppModel.swift    # @Observable, builds the feature graph
    │   │       ├── AppView.swift     # window layout, no feature logic
    │   │       ├── Components/       # subviews only this feature uses
    │   │       ├── Platform/         # AppKit bridging: NSViewRepresentable, NSWindow
    │   │       └── Previews/         # #if DEBUG preview doubles
    │   ├── Models/           # Sendable value types, one per file
    │   ├── Clients/          # side effects behind protocols, one folder per client
    │   │   ├── Git/{GitClient,LiveGitClient}.swift
    │   │   └── FolderPicker/{FolderPickerClient,LiveFolderPickerClient}.swift
    │   ├── ClientsTestSupport/   # fakes; never linked into the app
    │   ├── Storage/          # SwiftData models, schema versions, container
    │   ├── Worktrees/        # watched file and git state, read by more than one feature
    │   ├── Syntax/           # token kinds + highlighter, over the Rust crate. No colours.
    │   └── DesignSystem/     # Theme.swift + Views/, Modifiers/, Shapes/
    └── Tests/
        ├── Features/<Name>FeatureTests/   # mirrors Sources/Features
        └── <Module>Tests/                 # one suite file per source file
```

## Where a new file goes

| Adding | Goes in |
| --- | --- |
| A user-facing feature | its own target under `Sources/Features/<Name>Feature/`, mirroring `AppFeature`'s shape |
| A subview used by one feature | that feature's `Components/` |
| A view, modifier or shape used by two features | `DesignSystem/Views`, `/Modifiers`, `/Shapes` |
| A design token | `DesignSystem/Theme.swift` |
| Anything touching disk, network, processes or the clock | a protocol plus its `Live` implementation in `Clients/<Subject>/` |
| A fake for that protocol | `ClientsTestSupport/` |
| A persisted type | `Storage/`, versioned in `WorkspaceSchemaV1` |
| Live state two features both read | `Worktrees/`, not whichever feature needed it first |
| A plain value type | `Models/`, one type per file named after the type |
| AppKit bridging | the feature's `Platform/` |
| A language for the editor to highlight | `../../packages/syntax-highlighter`, not here. See its `AGENTS.md`. |
| A colour for a token kind | `DesignSystem/Theme.swift`, paired in `EditorFeature/Platform/SyntaxAttributes.swift` |

Organise by feature, not by type: a feature's view, model and subviews sit together.
Name files after the single type they hold.

A new feature target needs `path: "Sources/Features/<Name>Feature"` and its test
target `path: "Tests/Features/<Name>FeatureTests"`. SwiftPM looks directly under
`Sources` and `Tests` by default, so without those the build cannot find the files.

## Rules the compiler cannot check

- **Keep the app target thin.** `Herder/` declares scenes and injects live clients.
  Behaviour goes in `HerderKit`.
- **Point dependencies downward only.** Features depend on `Models`, `Clients`,
  `Storage`, `Worktrees` and `DesignSystem`. Two features that need to talk do it
  through `AppFeature` or a shared model, so add each new feature target to
  `AppFeature`'s dependencies.
- **Key paths with `PathKey`, never with a raw `URL`.** The same folder arrives
  spelled differently from a bookmark, from `git` and from the file watcher, and
  `standardizedFileURL` does not resolve symlinks. A dictionary keyed on `URL`
  looks like it works and silently misses.
- **Observe models directly.** `@Observable` classes read straight from views,
  injected through `init` or `@Environment`. Reach for a separate ViewModel layer
  only when direct observation has actually failed.
- **Let per-target isolation do the work.** `Package.swift` sets `MainActor`
  isolation for UI targets and `nonisolated` for `Models`/`Clients`, so views and
  models need no `@MainActor` annotation. New targets take `ui` or `core` settings.
- **Reference `Theme` instead of literals** for spacing, colour, radius and size.
- **Keep token kinds and colours apart.** `Syntax` says what a span of code *is*
  and names no colour; `DesignSystem` holds the colours and knows no kinds;
  `EditorFeature` is the one place that pairs them. That is what lets a grammar
  be added without touching the theme, and the theme be changed without touching
  a grammar.
- **Tokens are only ever applied to the string they were found in.** `SourceText`
  binds text to its tokens so the pair cannot come apart, and `EditorModel`
  checks the text still matches before letting a highlight land. Colour does
  arrive after the text — a quarter of a second of query compilation must not sit
  between a click and the file appearing — and that is safe only because of those
  two things. A `SourceText` with no tokens is incomplete; one with another
  string's tokens paints the wrong characters, or throws.
- **A reload that finds the same text must change nothing.** The worktree
  notifies every observer when any folder in it is read, so expanding a folder in
  the explorer reloads the open file. Compare the text, not the whole `Content`:
  a freshly read one carries no tokens yet, so comparing values drops the colour
  already on screen and flickers it back.

## Commands

Run from this directory, or append `apps/herder` to the root `justfile` equivalents.

```sh
just test          # Swift Testing suites via xcodebuild, no app host
just build         # regenerates the project, then builds
just dev           # build and run with output in the terminal
just uitest        # XCTest UI suite; slow, launches the app
just syntax        # rebuild the Rust crate and refresh its XCFramework
```

`Herder.xcodeproj` is generated and gitignored. Files under `HerderKit` are picked
up by SwiftPM, so only changes to `Herder/` or `UITests/` need `just project`.

`HerderKit` has a `.binaryTarget` on `Vendor/HerderSyntaxFFI.xcframework`, built
from `../../packages/syntax-highlighter` and gitignored like the project file. `test`, `build`
and `bootstrap` all depend on the `syntax` recipe, so it is never stale; a fresh
clone needs `just bootstrap` before SwiftPM will resolve the package, and needs a
Rust toolchain for that to work.

Tests are Swift Testing: structs for suites, `#require` to unwrap, `#expect` for
everything else. They run in parallel, so anything process-global needs a unique
path per test.
