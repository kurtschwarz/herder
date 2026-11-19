//! The one place the daemon runs the `git` CLI.
//!
//! `gix` serves every operation except the ones listed here, and each entry
//! says why. Nothing outside this module spawns `git`, so this list is the
//! whole list.
//!
//! | Operation | Why `gix` is not enough |
//! | --- | --- |
//! | `shortstat` (and `change_summary`, which ends in it) | `gix` has no combined staged-plus-unstaged diff of the working tree against a commit. |
//! | `changed_files` | The same, and `gix`'s rename pairing can differ from `git diff -M`, which the app has always shown. |

use crate::protocol::{GitError, GitErrorCode};
use std::path::Path;
use std::process::{Command, Stdio};

/// Runs `git -C dir args...` and returns its standard output. `Ok(None)` when
/// git exits non-zero, which for the read-only questions asked here means "no
/// answer" and not a failure; `Err` only when git could not be run at all.
pub fn run(dir: &Path, args: &[&str]) -> Result<Option<Vec<u8>>, GitError> {
    let output = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(args)
        .env("GIT_TERMINAL_PROMPT", "0")
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .map_err(|error| GitError {
            code: GitErrorCode::Failed,
            message: format!("could not run git: {error}"),
        })?;
    Ok(output.status.success().then_some(output.stdout))
}
