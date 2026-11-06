# ghostty-vt

Builds libghostty-vt, the terminal-state half of Ghostty, into an XCFramework for
`apps/herder`. It holds no Ghostty source: `GHOSTTY_COMMIT` is the one commit it
builds, `just build` downloads that and compiles it, and `target/` (gitignored)
holds both.

Needs Zig 0.17.x (`brew install zig`), the way the syntax highlighter needs Rust.

libghostty-vt's API is not stable. Changing the commit is a deliberate change:
build, then fix what `TerminalUI` breaks. Nothing outside `TerminalUI` may import
it; see `apps/herder/docs/ARCHITECTURE.md`.
