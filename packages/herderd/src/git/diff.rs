//! Differences between the working tree and a commit, which `git` itself
//! reports (see [`cli`](super::cli) for why).

use super::cli;
use super::natural;
use crate::protocol::{ChangeSummary, ChangedFile, FileChange, GitError};
use std::collections::HashMap;
use std::path::Path;

/// Lines inserted and deleted in tracked files between `sha` and the working
/// tree, staged and unstaged together.
pub fn shortstat(root: &Path, sha: &str) -> Result<Option<ChangeSummary>, GitError> {
    if sha.starts_with('-') {
        return Ok(None);
    }
    let output = cli::run(root, &["diff", "--no-ext-diff", "--shortstat", sha])?;
    Ok(output.map(|bytes| parse_shortstat(&String::from_utf8_lossy(&bytes))))
}

/// Tracked files whose working copy differs from `sha`, with counts, sorted by
/// path. Two runs rather than one `--raw`: `--name-status` has the status
/// letters and `--numstat` has the counts, and neither has both.
pub fn changed_files(root: &Path, sha: &str) -> Result<Vec<ChangedFile>, GitError> {
    if sha.starts_with('-') {
        return Ok(Vec::new());
    }
    let common = ["diff", "--no-ext-diff", "--no-textconv", "-M", "-z"];
    let run = |mode: &str| -> Result<Option<Vec<u8>>, GitError> {
        let mut args = common.to_vec();
        args.extend([mode, sha]);
        cli::run(root, &args)
    };
    let (Some(names), Some(counts)) = (run("--name-status")?, run("--numstat")?) else {
        return Ok(Vec::new());
    };
    Ok(parse_changed_files(&String::from_utf8_lossy(&names), &String::from_utf8_lossy(&counts)))
}

/// ` 3 files changed, 107 insertions(+), 19 deletions(-)`. Either count is left
/// out when it is zero, and the whole line when nothing changed, so anything
/// with no count in it reads as no change.
fn parse_shortstat(output: &str) -> ChangeSummary {
    let mut summary = ChangeSummary { insertions: 0, deletions: 0 };
    for part in output.split(',') {
        let mut words = part.split_whitespace();
        let (Some(count), Some(unit)) = (words.next(), words.next()) else { continue };
        let Ok(count) = count.parse() else { continue };
        if unit.starts_with("insertion") {
            summary.insertions = count;
        } else if unit.starts_with("deletion") {
            summary.deletions = count;
        }
    }
    summary
}

/// `-z` is the only safe way to read paths back. In `--name-status` a rename is
/// `R100`, the old path and the new one; in `--numstat` it is the counts with an
/// empty path, then the old path and the new one. A binary file counts as `-`,
/// which reads as no lines.
fn parse_changed_files(name_status: &str, numstat: &str) -> Vec<ChangedFile> {
    let mut counts: HashMap<&str, (u64, u64)> = HashMap::new();
    let stats: Vec<&str> = numstat.split('\0').collect();
    let mut index = 0;
    while index < stats.len() {
        let fields: Vec<&str> = stats[index].splitn(3, '\t').collect();
        index += 1;
        if fields.len() != 3 {
            continue;
        }
        let mut path = fields[2];
        if path.is_empty() && index + 1 < stats.len() {
            path = stats[index + 1];
            index += 2;
        }
        counts.insert(path, (fields[0].parse().unwrap_or(0), fields[1].parse().unwrap_or(0)));
    }

    let mut files = Vec::new();
    let names: Vec<&str> = name_status.split('\0').filter(|name| !name.is_empty()).collect();
    let mut index = 0;
    while index < names.len() {
        let code = names[index];
        index += 1;
        let Some(letter) = code.chars().next() else { continue };
        if index >= names.len() {
            continue;
        }
        let mut path = names[index];
        index += 1;
        let mut previous = None;
        let status = match letter {
            'A' => FileChange::Added,
            'D' => FileChange::Deleted,
            'R' | 'C' => {
                if index >= names.len() {
                    continue;
                }
                // A copy is a new file as far as the base is concerned.
                if letter == 'R' {
                    previous = Some(path.to_string());
                }
                path = names[index];
                index += 1;
                if letter == 'R' { FileChange::Renamed } else { FileChange::Added }
            }
            _ => FileChange::Modified,
        };
        let (insertions, deletions) = counts.get(path).copied().unwrap_or((0, 0));
        files.push(ChangedFile {
            path: path.to_string(),
            previous_path: previous,
            status,
            insertions,
            deletions,
        });
    }
    files.sort_by(|a, b| natural::compare(&a.path, &b.path));
    files
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shortstat_reads_either_count_and_nothing() {
        assert_eq!(
            parse_shortstat(" 3 files changed, 107 insertions(+), 19 deletions(-)\n"),
            ChangeSummary { insertions: 107, deletions: 19 }
        );
        assert_eq!(
            parse_shortstat(" 1 file changed, 2 deletions(-)"),
            ChangeSummary { insertions: 0, deletions: 2 }
        );
        assert_eq!(parse_shortstat(""), ChangeSummary { insertions: 0, deletions: 0 });
    }

    #[test]
    fn changed_files_join_status_and_counts_and_follow_renames() {
        let names = "M\0a.txt\0R100\0old.txt\0new.txt\0A\0b.bin\0";
        let counts = "1\t2\ta.txt\0-\t-\tb.bin\x003\t4\t\0old.txt\0new.txt\0";

        let files = parse_changed_files(names, counts);

        assert_eq!(
            files,
            vec![
                ChangedFile {
                    path: "a.txt".into(),
                    previous_path: None,
                    status: FileChange::Modified,
                    insertions: 1,
                    deletions: 2
                },
                ChangedFile {
                    path: "b.bin".into(),
                    previous_path: None,
                    status: FileChange::Added,
                    insertions: 0,
                    deletions: 0
                },
                ChangedFile {
                    path: "new.txt".into(),
                    previous_path: Some("old.txt".into()),
                    status: FileChange::Renamed,
                    insertions: 3,
                    deletions: 4
                },
            ]
        );
    }
}
