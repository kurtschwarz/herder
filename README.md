# Herder

A monorepo. Today it holds one macOS app; more apps and services go beside it.

## Layout

```
herder/
├── justfile                  # forwards every task to an app or service
└── apps/
    └── herder/               # the macOS app
        ├── AGENTS.md         # structure and conventions, for agents
        ├── justfile          # how to build, test and run this app
        ├── project.yml       # source of truth for Herder.xcodeproj
        ├── Herder/           # thin app target: entry point and glue only
        ├── Packages/
        │   └── HerderKit/    # all the code, split into modules
        └── UITests/          # XCTest, since Swift Testing has no UI automation
```

New apps go in `apps/<name>/`. Services go in `services/<name>/`. Code shared
between more than one of them goes in a package under `packages/` at the root, not
inside an app.

## Getting started

```sh
just bootstrap apps/herder   # generates Herder.xcodeproj
just test apps/herder        # fast module tests, no app host
just dev apps/herder         # build and run, logs in the terminal
```

Requires Xcode 26+ and `brew install just xcodegen`.

## Commands

Every recipe takes the path to an app or service, so the same verbs work across the
repo as it grows:

| Command | Does |
| --- | --- |
| `just build <dir>` | Build it |
| `just test <dir>` | Run its tests. Extra arguments pass through: `just test apps/herder -only-testing:ClientsTests` |
| `just dev <dir>` | Build and run it, with its output in your terminal |
| `just bootstrap <dir>` | Set it up in a fresh clone |
| `just clean <dir>` | Remove its build artifacts |
| `just in <dir> <recipe>` | Run anything else it defines, e.g. `just in apps/herder uitest` |
| `just test-all` | Test every app and service |
| `just list` | List the apps and services |

The root `justfile` only forwards. Each app or service owns a `justfile` with those
recipe names, which is what lets a Swift app and, later, a Go service sit side by
side without the root knowing anything about either toolchain. `just` on its own
lists every recipe, in either place.

Stopping `just dev` with either Ctrl-C or Cmd-Q exits 0 and prints nothing extra.
That takes a signal trap at each layer: Ctrl-C goes to every process in the
terminal's foreground group, so without one, the recipe's own shell dies by signal
and `just` reports an ordinary quit as a failed recipe. Real failures still
propagate — a failing test exits 1.

## How the app is put together

The Xcode target is deliberately almost empty. It owns the `@main` entry point,
`Info.plist`, entitlements, signing and assets, and nothing else. Everything real
lives in the local Swift package `apps/herder/Packages/HerderKit`, split into
modules:

| Module | Job | Default isolation |
| --- | --- | --- |
| `Models` | Plain `Sendable` value types. No SwiftUI. | `nonisolated` |
| `Clients` | Side effects behind protocols: disk, network, processes, clocks. | `nonisolated` |
| `ClientsTestSupport` | Fakes for those protocols. Never linked into the app. | `nonisolated` |
| `Storage` | SwiftData `@Model` classes, their schema versions and the container. The one module that owns reference types. | `MainActor` |
| `DesignSystem` | Shared views, styles, tokens. | `MainActor` |
| `AppFeature` | Root view, navigation, composes features. | `MainActor` |

This buys four things: the tests run in seconds with no app host, module
boundaries are enforced by the compiler instead of convention, previews work, and
the project file stops being a merge battleground.

Run the module tests with `just test`. It takes arguments, so
`just test -only-testing:ClientsTests` works too. Tests run through `xcodebuild`, not
`swift test`, because PhosphorSwift's icons are an asset catalog that only Xcode's
build system bundles.

### Adding a feature

One module per feature, under `Sources/Features/`:

```
Features/EditorFeature/
├── EditorView.swift
├── EditorModel.swift      # @Observable, owns state and logic
├── Components/            # subviews only this feature uses
├── Platform/              # AppKit bridging, if it needs any
└── Previews/              # #if DEBUG doubles
```

Organise by feature, not by type. No top-level `Views/` or `ViewModels/` folders —
those become junk drawers. Within a module, group by role: `DesignSystem` splits
into `Views/`, `Modifiers/` and `Shapes/`, and each client in `Clients` keeps its
protocol and live implementation together in `Clients/<Subject>/`.

Register it in `Package.swift` with the `ui` settings, add a matching test target,
and depend on it from `AppFeature`:

```swift
.target(
    name: "EditorFeature",
    dependencies: ["Models", "Clients", "DesignSystem"],
    path: "Sources/Features/EditorFeature",
    swiftSettings: ui
),
.testTarget(
    name: "EditorFeatureTests",
    dependencies: ["EditorFeature", "ClientsTestSupport"],
    path: "Tests/Features/EditorFeatureTests",
    swiftSettings: ui
),
```

The `path` is what buys the `Features/` folder: SwiftPM maps a target name straight
onto `Sources/<name>` unless told otherwise.

The dependency graph only points downward. Features depend on `Clients`, `Models`,
`Storage` and `DesignSystem`, never on each other. If two features need to talk,
that goes through `AppFeature` or a shared model.

### Concurrency

Swift 6.2's per-target default isolation does the heavy lifting. UI modules default
to `@MainActor`, so views and `@Observable` models need no annotation. `Models` and
`Clients` stay `nonisolated` so they can do real background work.

### Dependencies and testability

Anything with side effects lives behind a protocol in `Clients`. Live
implementations are injected from the app target in `Herder/HerderApp.swift`; tests
pass fakes from `ClientsTestSupport`. Pass them via `init` into `@Observable`
models, or through `@Environment` for views. No DI framework until it hurts.

### Persistence

`Storage` holds the SwiftData layer. Its schema is versioned from the first
release (`WorkspaceSchemaV1`) with a `SchemaMigrationPlan` beside it, so the first
migration is written against a schema that has a name.

`WorkspaceContainer` is the only place that knows the schema, the migration plan
and where the store lives. The app calls `.live()`, tests and previews call
`.inMemory()`, and neither repeats the setup. CloudKit is off: a workspace carries
a security-scoped bookmark, which only resolves on the Mac and account that made
it.

Reads go through `@Query` against the container the app target injects with
`.modelContainer(_:)`. Writes go through `WorkspaceStore`, so the rules about
which folders qualify, what they are called and how they are ordered live in one
place. Tests build a real in-memory container rather than faking the store, which
means they exercise the shipping schema, constraints and sort descriptors; only
the two OS-touching clients, `BookmarkClient` and `GitClient`, are faked.

## Testing

Test targets mirror source modules one to one. Unit tests are Swift Testing; UI and
performance tests stay in XCTest, in `UITests/`.

Conventions that pay off:

- **Use structs for suites.** Each test gets a fresh instance, so state can't leak
  and there's no `setUp`/`tearDown` to maintain.
- **Tests run in parallel by default.** Anything process-global — `UserDefaults`,
  temp directories — needs a unique path per test. See `LiveFileClientTests` for
  the pattern.
- **`#require` to unwrap or fail early, `#expect` for everything else.**
- **`confirmation { }`** for "this callback fired N times" style async checks.
- **Tags** (`.tags(.slow)`) for filtering in the test navigator.

## The project file

`Herder.xcodeproj` is generated from `apps/herder/project.yml` and is gitignored, so
there is no `.pbxproj` in version control to conflict over. Adding or removing a
file in `Herder/` or `UITests/` means re-running `just project`; files inside
`HerderKit` are picked up by SwiftPM automatically and need no regeneration.

Day to day you rarely touch it: Xcode handles signing, entitlements and the `@main`
entry point, SwiftPM handles everything else, and the test loop is `just test` in a
few seconds instead of booting the whole app.
