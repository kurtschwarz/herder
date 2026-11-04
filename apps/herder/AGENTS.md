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
| A plain value type | `Models/`, one type per file named after the type |
| AppKit bridging | the feature's `Platform/` |

Organise by feature, not by type: a feature's view, model and subviews sit together.
Name files after the single type they hold.

A new feature target needs `path: "Sources/Features/<Name>Feature"` and its test
target `path: "Tests/Features/<Name>FeatureTests"`. SwiftPM looks directly under
`Sources` and `Tests` by default, so without those the build cannot find the files.

## Rules the compiler cannot check

- **Keep the app target thin.** `Herder/` declares scenes and injects live clients.
  Behaviour goes in `HerderKit`.
- **Point dependencies downward only.** Features depend on `Models`, `Clients`,
  `Storage` and `DesignSystem`. Two features that need to talk do it through
  `AppFeature` or a shared model, so add each new feature target to `AppFeature`'s
  dependencies.
- **Observe models directly.** `@Observable` classes read straight from views,
  injected through `init` or `@Environment`. Reach for a separate ViewModel layer
  only when direct observation has actually failed.
- **Let per-target isolation do the work.** `Package.swift` sets `MainActor`
  isolation for UI targets and `nonisolated` for `Models`/`Clients`, so views and
  models need no `@MainActor` annotation. New targets take `ui` or `core` settings.
- **Reference `Theme` instead of literals** for spacing, colour, radius and size.

## Commands

Run from this directory, or append `apps/herder` to the root `justfile` equivalents.

```sh
just test          # Swift Testing suites via xcodebuild, no app host
just build         # regenerates the project, then builds
just dev           # build and run with output in the terminal
just uitest        # XCTest UI suite; slow, launches the app
```

`Herder.xcodeproj` is generated and gitignored. Files under `HerderKit` are picked
up by SwiftPM, so only changes to `Herder/` or `UITests/` need `just project`.

Tests are Swift Testing: structs for suites, `#require` to unwrap, `#expect` for
everything else. They run in parallel, so anything process-global needs a unique
path per test.
