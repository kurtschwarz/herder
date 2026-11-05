# herder-syntax (Rust)

Turns source text into coloured spans for Herder's editor pane. Tree-sitter
grammars behind a C ABI, consumed by the macOS app's `Syntax` Swift module as an
XCFramework.

`../../README.md` carries the rationale for Rust over the Swift tree-sitter
packages; this file is the rules.

## Layout

```
packages/syntax-highlighter/
├── Cargo.toml              # one dependency line per grammar
├── rust-toolchain.toml     # pinned, like Package.resolved
├── .cargo/config.toml      # macOS deployment target, matched to the app's
├── justfile                # build (XCFramework), test, dump
├── include/
│   ├── herder_syntax.h     # hand-written, matched to src/lib.rs
│   └── module.modulemap    # makes it `import HerderSyntaxFFI`
├── examples/dump.rs        # prints a file's tokens, for debugging colour
└── src/
    ├── lib.rs              # the whole FFI surface: four functions
    ├── kind.rs             # token kinds, and the capture names that produce them
    ├── language.rs         # the grammar table, and matching a file to one
    └── highlight.rs        # parse, walk the events, convert offsets
```

## Adding a language

Two edits, both in this crate. Nothing in Swift changes and nothing above the
crate can tell a language was added.

1. A dependency in `Cargo.toml`, in the alphabetical block:

   ```toml
   tree-sitter-elixir = "0.3"
   ```

2. A row in `LANGUAGES` in `src/language.rs`, in alphabetical order:

   ```rust
   Language {
       name: "elixir",
       aliases: &["ex"],
       extensions: &["ex", "exs"],
       filenames: &[],
       interpreters: &[],
       injection_only: false,
       grammar: || tree_sitter_elixir::LANGUAGE.into(),
       highlights: || tree_sitter_elixir::HIGHLIGHTS_QUERY.to_string(),
       injections: empty,
       locals: empty,
   },
   ```

Then add a line to the `every_language_highlights_something` table in
`src/highlight.rs` and run `just test`. That test is the one that catches a row
whose queries compile but produce nothing, which is the failure mode that would
otherwise ship silently.

Six things to watch, each of which has already bitten:

- **The query constant is named inconsistently upstream.** Some crates export
  `HIGHLIGHTS_QUERY` and some `HIGHLIGHT_QUERY`. The compiler says which.
- **Check the capture names the grammar actually uses, and dump a real file.**
  A grammar can compile, produce tokens and pass every test here while being
  visibly wrong, because `configure` resolves an unknown capture to the longest
  entry in `CAPTURES` that fits. gitignore captures its paths as
  `@string.special.path`, whose longest match was `string.special` — so every
  path in the file came out the colour reserved for `\n` and `*`. `just dump`
  on a real file is the only thing that catches this.
- **Some grammars only make sense as an extension of another.** TypeScript's
  query covers what it adds to JavaScript, so the two are concatenated; see
  `typescript_highlights`.
- **A grammar that injects another names it in `injections.scm`.** Add that name
  to the target language's `aliases` or the injection silently does nothing.
  `by_name` also falls back to `interpreters` and trims the name, because an
  injected name can be the text of a captured node rather than a literal in the
  query: a justfile shebang recipe injects ` python3`, space and all.
- **An injection into a node whose text all belongs to its children needs
  `injection.include-children`.** Without it the injected range comes out empty
  and the layer contributes nothing, which reads as a grammar that does not work
  rather than a query that does not. It bit markdown's paragraphs and just's
  recipe bodies — most of a justfile — and both are fixed by appending a
  corrected pattern rather than editing the bundled one. See
  `markdown_injections` and `just_injections`.
- **A grammar crate that depends on `tree-sitter` directly cannot be used at
  all.** Only one package in a dependency graph may link the native
  `tree-sitter` library, so such a crate conflicts with the version
  `tree-sitter-highlight` pulls in and Cargo refuses to resolve. The usable ones
  depend on `tree-sitter-language` and keep `tree-sitter` as a dev dependency.
  Check this before choosing a crate: the error lists versions that "meet the
  requirements" and buries the `links` collision below them, so it reads like a
  version-range problem that no range will fix. It ruled out the crate actually
  named `tree-sitter-just`, which is why the just row is served by a different
  grammar under a renamed dependency.
- **Not every grammar is published under `tree-sitter-<name>`.** gitignore's
  only maintained crate is `konomanoasa-tree-sitter-gitignore`, so it is renamed
  in `Cargo.toml` and `language.rs` reads like every other row. Prefer a crate
  from `tree-sitter` or `tree-sitter-grammars` where one exists; when taking an
  individual's, read its `grammar.js` and `LICENSE` first, since a build script
  compiling vendored C is more trust than an ordinary dependency.

## Styling a capture better

`CAPTURES` in `src/kind.rs` pairs a capture name with a kind, and
`HighlightConfiguration::configure` matches a capture against the longest entry
whose dotted parts all appear in it. A grammar nobody has thought about is
therefore coarsely styled rather than unstyled.

So a language whose colours are nearly right wants a *more specific* row, not a
new kind. `("string.special.path", Kind::String)` is the worked example in the
table: it exists because gitignore's paths were resolving to `string.special`
and coming out as escapes. One row fixed every path in the file, changed
`@string.special` for nobody else, and would do the same for the next grammar
that uses the same capture.

Adding a `Kind` is a bigger change: it has to be mirrored in
`SyntaxTokenKind.swift` and given a colour in `Theme.swift`, and
`SyntaxTests.everyKindTheCrateDefinesHasACaseHere` fails until both are done.

## Rules the compiler cannot check

- **Offsets leave here in UTF-16.** Tree-sitter counts bytes; `NSTextStorage`
  indexes UTF-16 code units. `to_utf16` converts before anything is handed over,
  because a conversion left to the caller is one that gets forgotten until a
  file with an emoji in it paints two characters to the left.
- **The header is hand-written and has to be kept in step with `lib.rs`.** It is
  four functions and one struct; a generator would be more machinery than it
  saves. Changing a signature means changing both.
- **Nothing here names a colour.** A kind says what a token *is*. The pairing
  with a colour is in `EditorFeature/Platform/SyntaxAttributes.swift`, so a
  retheme never reaches this crate.
- **Allocate and free on the same side.** `hdr_highlight` hands out a buffer
  Rust owns; Swift copies it out and calls `hdr_tokens_free`. Nothing is freed
  across the boundary.
- **`panic = "abort"`.** A panic must not unwind through `extern "C"`. Keep
  `expect` for things that cannot happen and return an empty token run for
  everything a reader might actually hit.
- **A grammar whose queries do not compile leaves its files plain.** It trips a
  `debug_assert` in a debug build and is swallowed in release: a reader can do
  nothing about it, and an unhighlighted file is better than no file.

## Commands

Run from this directory, or append `packages/syntax-highlighter` to the root `justfile`
equivalents.

```sh
just build         # universal static lib, wrapped as target/HerderSyntaxFFI.xcframework
just test          # cargo test, then clippy with warnings denied
just dump <file>   # print a file's tokens, to see why something is the wrong colour
just bootstrap     # add the Rust targets for both architectures
```

`just build` here only produces the XCFramework. Copying it into
`apps/herder/Packages/HerderKit/Vendor/` is the app's `syntax` recipe, which
every recipe that compiles Swift depends on: a stale static library links
without complaint, and the app would highlight with yesterday's grammars.

Universal because Xcode builds macOS Release for both architectures. A Debug
build sets `ONLY_ACTIVE_ARCH` and uses one slice.
