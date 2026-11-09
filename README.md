# Herder

A monorepo. Today it holds one macOS app; more apps and services go beside it.

## Layout

```
herder/
├── justfile                  # forwards every task to an app or service
├── apps/
│   └── herder/               # the macOS app
│       ├── AGENTS.md         # where a new file goes; points at docs/ARCHITECTURE.md
│       ├── docs/
│       │   └── ARCHITECTURE.md   # the rulebook: layers, state, concurrency
│       ├── justfile          # how to build, test and run this app
│       ├── project.yml       # source of truth for Herder.xcodeproj
│       ├── scripts/          # check-boundaries.sh, the import rules a compiler can't see
│       ├── Herder/           # thin app target: entry point and resources only
│       ├── HerderKit/        # all the code, split into modules
│       └── UITests/          # XCTest, since Swift Testing has no UI automation
└── packages/
    └── herder-syntax-highlighter/   # Rust: tree-sitter grammars behind a C ABI
```

New apps go in `apps/<name>/`. Services go in `services/<name>/`. A package under
`packages/` is for code that does not belong inside one app: either because more
than one of them uses it, or because it is not written in the app's language.
`packages/herder-syntax-highlighter` is the second kind — Rust, consumed by the macOS app as an
XCFramework.

**`apps/herder/docs/ARCHITECTURE.md` is the rulebook** for the app, and it wins
over this file. What is here is the monorepo and a tour; what is there is the
layering, the dependency rules, the state model and the conventions, in enough
detail to settle an argument.

## Getting started

```sh
just bootstrap apps/herder   # builds the syntax crate, generates Herder.xcodeproj
just test apps/herder        # fast module tests, no app host
just dev apps/herder         # build and run, logs in the terminal
```

Requires Xcode 26+, `brew install just xcodegen`, and a Rust toolchain
(`brew install rustup && rustup-init`). `just bootstrap` installs the Rust
targets it needs.

`HerderKit` has a `.binaryTarget` pointing at an XCFramework built from
`packages/herder-syntax-highlighter`, so a fresh clone must run `just bootstrap apps/herder` before
the Swift package will resolve. Every recipe that compiles Swift rebuilds the
crate first: a stale static library would link without complaint and highlight
with yesterday's grammars.

## Commands

Every recipe takes the path to an app or service, so the same verbs work across the
repo as it grows:

| Command | Does |
| --- | --- |
| `just build <dir>` | Build it |
| `just test <dir>` | Run its tests. Extra arguments pass through: `just test apps/herder -only-testing:CoreTests` |
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
`Info.plist`, entitlements, signing and assets, and links exactly one product.
Everything real lives in the local Swift package `apps/herder/HerderKit`,
split into modules:

| Module | Job | Default isolation |
| --- | --- | --- |
| `Core` | Value types, service protocols, and the app's live state. Imports only `Foundation` and `Observation` — never SwiftUI, AppKit or the Rust module. | `nonisolated` |
| `Services` | The implementations of Core's protocols: disk, git, the file watcher, the sandbox, the clock, persistence, the syntax engine. The only module that links the FFI. | `nonisolated` |
| `TestSupport` | A fake for every protocol, `#if DEBUG` so a release build links an empty module. Features depend on it for their previews. | `nonisolated` |
| `DesignSystem` | Shared views, styles, tokens. | `MainActor` |
| `<Name>Feature` | One per feature, under `Sources/Features/<Name>/`. UI and feature state. | `MainActor` |
| `AppFeature` | The composition root. Not a feature. | `MainActor` |

The rule that holds the rest up: **a feature may import `Core`, `DesignSystem`
and `TestSupport`, and nothing else.** It never sees a concrete service and never
sees another feature. Four of those edges are enforced by target dependencies in
`Package.swift`; the ones a dependency graph cannot express — Core staying free
of SwiftUI, the Rust module staying inside `Services`, no singletons anywhere —
are enforced by `apps/herder/scripts/check-boundaries.sh` — `just check` from
`apps/herder`, or `just in apps/herder check` from here.

**`AppFeature` is the composition root, despite the name, and it is a module
rather than the Xcode target.** The project file is generated, so every file
added under `Herder/` costs a `just project` run, while files under `HerderKit`
are picked up by SwiftPM on their own — and composition code changes often. So
`AppEnvironment` lives there, it is the only place in the codebase that names a
concrete service type, and it is the one module allowed to import `Services`.

Two features that want the same answer go through `Core`, not through each other
and not through `AppFeature`. The file tree draws a worktree's files and the
sidebar says which worktrees have uncommitted work, so that state is a
`Workspace` in `Core/Workspace/` — below both of them, rather than inside
whichever feature happened to need it first.

This buys four things: the tests run in seconds with no app host, module
boundaries are enforced by the compiler instead of convention, previews work, and
the project file stops being a merge battleground.

Run the module tests with `just test`. It takes arguments, so
`just test -only-testing:CoreTests` works too. Tests run through `xcodebuild`, not
`swift test`, because PhosphorSwift's icons are an asset catalog that only Xcode's
build system bundles.

### State

Two levels, because the app has two:

- A **`Repository`** is a folder the user adopted and named. It is persisted, it
  has a sidebar position, and it holds a security-scoped bookmark — the one piece
  of state in the app that cannot be rebuilt from disk, because regenerating it
  means asking the user to find the folder again in an open panel. `RepositoryStore`
  owns the pool; each window lists some of it.
- A **`Workspace`** is one checkout: a repository's worktree, or a plain folder.
  It holds that checkout's listings, its git state and each feature's UI state.
  `WorkspaceRegistry` holds however many are open.

A feature takes `@Environment(Workspace.self)` and gets whichever one its window
resolved, so nothing ever asks "which is active?" — which is what keeps two
windows from disagreeing. Which workspace a window is showing belongs to the
window, in `WindowEnvironment`, along with that window's own editor, file tree
and sidebar models.

Opening a workspace is idempotent and closing is explicit, so switching away from
a worktree keeps it: its listings, its git state, and later its terminals and
agent sessions. What makes that affordable is that holding is cheap and
refreshing is not — a background workspace costs a file watcher, while a refresh
costs a `git status` for the whole repository — so **a workspace refreshes only
while a frontmost window is showing it**, and the rest accumulate their watcher's
events and act on them in one go when they come forward.

### Adding a feature

One module per feature, under `Sources/Features/`. The folder does not repeat the
suffix:

```
Features/Editor/              # module EditorFeature
├── EditorView.swift          # the entry point, and usually the only public view
├── EditorModel.swift         # @Observable, owns state and logic
├── Components/               # subviews only this feature uses
└── Platform/                 # AppKit bridging, if it needs any
```

Organise by feature, not by type. No top-level `Views/` or `ViewModels/` folders —
those become junk drawers. Within a module, group by role: `DesignSystem` splits
into `Views/`, `Modifiers/` and `Shapes/`, service protocols sit in
`Core/Services/` and their implementations in `Services/<Area>/`.

Register it in `Package.swift` with the `ui` settings, add a matching test target,
and depend on it from `AppFeature`:

```swift
.target(
    name: "EditorFeature",
    dependencies: ["Core", "DesignSystem", "TestSupport"],
    path: "Sources/Features/Editor",
    swiftSettings: ui
),
.testTarget(
    name: "EditorFeatureTests",
    dependencies: ["EditorFeature", "Core", "TestSupport"],
    path: "Tests/Features/EditorFeatureTests",
    swiftSettings: ui
),
```

Both `path`s are load-bearing: SwiftPM maps a target name straight onto
`Sources/<name>` unless told otherwise, so without them the build cannot find the
files at all.

Keep the public surface small — usually one view and one model, with the model
exposing only what the composition root calls. Everything the feature drives
itself with stays `internal`, because its own view and its own tests are in the
same module.

Previews live at the bottom of the view file behind `#if DEBUG`, over fakes from
`TestSupport`. A preview that needs a service it cannot import is telling you the
preview should show the pane rather than the integration.

### Syntax highlighting

The editor's colours come from tree-sitter, which is a C library with a grammar
per language. Those grammars are driven from Rust, in `packages/herder-syntax-highlighter`, rather
than from Swift, for one reason: the `tree-sitter-highlight` crate already does
the two awkward parts. It resolves a grammar's capture names against a list of
names you recognize, longest dotted prefix first, so `@keyword.control.conditional`
finds `keyword` without anyone writing that rule; and it resolves injections, so
JavaScript inside HTML and the inline half of markdown work without layer logic
of ours. The Swift packages for the same grammars have neither, and would need
both hand-written.

Three places share the work, and none of them knows all of it:

- `packages/herder-syntax-highlighter` owns the grammars, the queries and the table matching a file
  to a language. It emits spans with a semantic kind and no opinion about colour.
- `Core` is the Swift face of that: `SyntaxTokenKind`, `SyntaxToken`, `SourceText`
  and the `SyntaxHighlighter` protocol. `Services/Highlighting/` is the one Swift
  file that imports the FFI, and it converts the C types to those at the boundary.
- `EditorFeature` pairs a kind with a colour from `DesignSystem`.

So adding a language touches one file in Rust and nothing in Swift, and retheming
touches `Theme.swift` and nothing else. `packages/herder-syntax-highlighter/AGENTS.md` has the
procedure for both.

The boundary speaks UTF-8 going in and UTF-16 offsets coming out, so neither side
converts: tree-sitter counts bytes and `NSTextStorage` indexes UTF-16, and a
conversion left to the caller is one that gets forgotten until a file with an
emoji in it paints its colours two characters to the left. **The crate converts
before handing a token over**, and there must not be a second conversion in
Swift.

The timing is the part that needed measuring rather than guessing. Highlighting a
file is a few hundred microseconds; compiling one language's queries is up to a
quarter of a second, because the work scales with the size of the *grammar* and
Swift's `parser.c` is 23 MB. So all of the perceived cost is that one-off
compile, and two things keep it off the reader's path: `AppEnvironment.start`
warms every grammar on a detached task at launch, and the editor publishes a
file's text as soon as it is read and lets colour follow. The second is what makes
a cold grammar survivable at all; the first means it rarely happens.

Colour arriving separately is only safe because tokens are offsets into a
particular string, and `EditorModel` checks that string is still the one on
screen before letting them land. That check replaces a generation counter and is
a better question to ask: a slow highlight for a file that was rewritten and
written back is still right, and a fast one for a file that has since changed is
not.

The cost is honest and worth stating: the grammars' parse tables are data, and
sixteen of them add about 15 MB per architecture to the binary. That total is
dominated by a few large grammars — Swift's generated parser alone is 23 MB of C
— so most languages are far cheaper than the average suggests: gitignore cost
54 KB. A second
toolchain also has to be present to build the app at all.

### Concurrency

Swift 6.2's per-target default isolation does the heavy lifting. UI modules default
to `@MainActor`, so views and `@Observable` models need no annotation. `Core` and
`Services` stay `nonisolated` so they can do real background work, and the stores
in `Core` are marked `@MainActor` one by one instead.

`NonisolatedNonsendingByDefault` is on everywhere, which is what gives
`@concurrent` its meaning: without it a plain `nonisolated async` function runs on
whichever actor called it, so the highlighter would parse a megabyte on the main
actor and stop the editor redrawing.

The bar is zero warnings. An escape hatch — `@unchecked Sendable`,
`nonisolated(unsafe)`, a `DispatchQueue` — carries a `// CONCURRENCY:` comment
saying why it is safe and what it could not be. There are three in the shipping
code, all at a C or AppKit boundary with no `async` equivalent.

### Dependencies and testability

Anything with side effects lives behind a protocol in `Core/Services/`. Live
implementations are constructed in `AppEnvironment` and nowhere else; tests pass
fakes from `TestSupport`. Pass them via `init` into `@Observable` models, or
through `@Environment` for views. No DI framework and no singletons — the
boundary script fails a build over `static let shared`.

### Sandbox

The app is not sandboxed. It creates git worktrees and will launch agents and
shells in the user's folders, and a child process in a sandbox cannot reach the
folders the app was granted. That rules out the Mac App Store; the entitlements
file is empty on purpose. Reads of a repository still go straight to disk rather
than through `git` (see `LiveGitClient`), and repositories still keep a bookmark
of their folder, which costs nothing and would be needed again if the sandbox came
back.

### Persistence

The source of truth for code is the disk and git. Herder persists only its own
state, as JSON under `~/Library/Application Support/Herder/`:

```
state.json                       # the repository pool, and an index of the windows
windows/<id>-<hash>.json         # one per window: what it lists, keeps open and shows
workspaces/<name>-<hash>.json    # one per workspace: its features' UI state
```

Everything goes through one protocol, `StateStore` in `Core`, which loads and
saves `Codable` values by key and knows nothing about what it is holding.
`FileStateStore` in `Services/Persistence/` is the implementation, an `actor`
writing atomically. `PersistenceStack` is the seam in front of it, so nothing
above `Services` names a storage type — which is how SwiftData, which this
replaced, could be deleted rather than unpicked.

Live `@Observable` state converts to and from snapshot structs. Never make an
`@Observable` class `Codable` directly: the macro's underscored backing storage
leaks into the encoded keys. Snapshots carry a `version`, and a new field is
added with `decodeIfPresent` and a default — that is the whole migration story,
and it is why there is no schema.

Two things that are not obvious:

- **Nothing is saved on termination.** `willTerminate` is a synchronous callback
  and writing is not, so a task started there races the process exiting. Saves
  are debounced a few hundred milliseconds instead, by their callers rather than
  by the store — because the one exception is the repository list, which writes
  immediately on every change. It holds the bookmarks, and a bookmark cannot be
  remade.
- **A key that reaches disk is data.** Renaming one is a migration, not a rename:
  the file tree's UI state is still stored under `explorer.expanded` after the
  feature was renamed, because changing the key would leave every saved blob
  unreachable and close every folder the user had open.

Each window has an id kept in `@SceneStorage` and a snapshot found by it. macOS
only restores the id on a clean quit, so a window without one adopts the window
used last when no other is open, and a new window beside another starts blank.

## Testing

Test targets mirror source modules: `CoreTests`, `ServicesTests`,
`AppFeatureTests`, and `Tests/Features/<Name>FeatureTests` for each feature. Unit
tests are Swift Testing; UI and performance tests stay in XCTest, in `UITests/`.

Conventions that pay off:

- **Use structs for suites.** Each test gets a fresh instance, so state can't leak
  and there's no `setUp`/`tearDown` to maintain.
- **Tests run in parallel by default.** Anything process-global — a temp
  directory, a state store, a git repository on disk — needs a unique path per
  test. See `LiveFileClientTests` for the pattern.
- **`#require` to unwrap or fail early, `#expect` for everything else.**
- **`confirmation { }`** for "this callback fired N times" style async checks.
- **Tags** (`.tags(.slow)`) for filtering in the test navigator.
- **Fake the OS, not your own code.** Feature models are tested against
  `TestSupport`'s fakes; `Core`'s stores are tested directly. The editor's tests
  use the *real* tree-sitter engine, because what colour a span gets is part of
  what the pane promises and a fake highlighter cannot check it.
- **Storage changes are tested against bytes this build did not write.** A
  fixture encoded by the current types proves nothing, because both sides move
  together.

## The project file

`Herder.xcodeproj` is generated from `apps/herder/project.yml` and is gitignored, so
there is no `.pbxproj` in version control to conflict over. Adding or removing a
file in `Herder/` or `UITests/` means re-running `just project`; files inside
`HerderKit` are picked up by SwiftPM automatically and need no regeneration.

Day to day you rarely touch it: Xcode handles signing, entitlements and the `@main`
entry point, SwiftPM handles everything else, and the test loop is `just test` in a
few seconds instead of booting the whole app.
