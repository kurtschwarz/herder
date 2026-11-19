//! The one place the daemon runs the `git` CLI.
//!
//! `gix` serves every operation except the ones listed here, and each entry
//! says why. Nothing outside this module spawns `git`, so this list is the
//! whole list.
//!
//! | Operation | Why `gix` is not enough |
//! | --- | --- |
//! | `add_worktree` | `gix` cannot create a linked worktree. *(not yet moved)* |
//! | `changed_files`, `shortstat` | `gix` has no combined staged-plus-unstaged diff, and its rename pairing can differ from `git diff -M`. *(not yet moved)* |
