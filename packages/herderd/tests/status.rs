//! The `status` scenarios of the app's old `LiveGitClient` tests, run against
//! the daemon.

mod common;

use common::Fixture;
use herderd::git;
use herderd::protocol::{Change, GitOp, GitResult, PathStatus};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

fn statuses(at: &Path) -> BTreeMap<String, PathStatus> {
    let op = GitOp::Status { path: at.to_str().unwrap().into() };
    match git::handle(&op).expect("git answers") {
        GitResult::Status { entries, .. } => {
            entries.into_iter().map(|entry| (entry.path, entry.status)).collect()
        }
        other => panic!("unexpected answer: {other:?}"),
    }
}

fn tracked(staged: Change, unstaged: Change) -> PathStatus {
    PathStatus::Tracked { staged, unstaged }
}

fn write(path: impl AsRef<Path>, contents: &str) {
    let path = path.as_ref();
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, contents).unwrap();
}

#[test]
fn finds_what_git_ignores_including_nested_rules_and_negations() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");
    write(repo.join(".gitignore"), "*.log\nbuild/\n!keep.log\n");
    write(repo.join("build/out.o"), "x");
    write(repo.join("sub/.gitignore"), "*.tmp\n");
    for name in ["debug.log", "keep.log"] {
        write(repo.join(name), "x");
    }
    for name in ["x.tmp", "y.txt"] {
        write(repo.join("sub").join(name), "x");
    }

    let found = statuses(&repo);

    assert_eq!(found["debug.log"], PathStatus::Ignored);
    // A nested ignore file counts, and is reported even though the folder
    // holding it collapsed as untracked.
    assert_eq!(found["sub"], PathStatus::Untracked);
    assert_eq!(found["sub/x.tmp"], PathStatus::Ignored);
    // Negated back in, so untracked rather than ignored.
    assert_eq!(found["keep.log"], PathStatus::Untracked);
}

/// An ignored or untracked folder is one entry, and nothing inside it is walked
/// or reported.
#[test]
fn collapses_ignored_and_untracked_folders() {
    let fixture = Fixture::new();
    let repo = fixture.repository("collapsing");
    write(repo.join(".gitignore"), "build/\n");
    for name in ["build", "fresh"] {
        write(repo.join(name).join("inside.txt"), "x");
    }

    let found = statuses(&repo);

    assert_eq!(found["build"], PathStatus::Ignored);
    assert_eq!(found["fresh"], PathStatus::Untracked);
    assert!(!found.contains_key("build/inside.txt"));
    assert!(!found.contains_key("fresh/inside.txt"));
}

#[test]
fn keeps_staged_and_unstaged_apart() {
    let fixture = Fixture::new();
    let repo = fixture.repository("columns");
    write(repo.join("staged.txt"), "one");
    fixture.git(&["add", "staged.txt"], &repo);
    write(repo.join("staged.txt"), "two");
    write(repo.join("README.md"), "edited");

    let found = statuses(&repo);

    assert_eq!(found["staged.txt"], tracked(Change::Added, Change::Modified));
    assert_eq!(found["README.md"], tracked(Change::Unchanged, Change::Modified));
}

#[test]
fn reports_a_deleted_file() {
    let fixture = Fixture::new();
    let repo = fixture.repository("gone");

    fixture.git(&["rm", "--quiet", "README.md"], &repo);

    // Nothing is left on disk, so no row will draw it: the entry is here only so
    // the folder it was in can say something went missing.
    assert_eq!(statuses(&repo)["README.md"], tracked(Change::Deleted, Change::Unchanged));
}

#[test]
fn reports_a_file_deleted_from_the_working_tree_only() {
    let fixture = Fixture::new();
    let repo = fixture.repository("removed");

    fs::remove_file(repo.join("README.md")).unwrap();

    assert_eq!(statuses(&repo)["README.md"], tracked(Change::Unchanged, Change::Deleted));
}

#[test]
fn reports_where_a_rename_came_from() {
    let fixture = Fixture::new();
    let repo = fixture.repository("renamed");
    // Content git cannot confuse with README.md's, or rename detection is free
    // to pair the two files the other way round.
    write(repo.join("moved.txt"), "something else entirely");
    fixture.git(&["add", "."], &repo);
    fixture.git(&["commit", "-m", "second"], &repo);
    fixture.git(&["mv", "moved.txt", "elsewhere.txt"], &repo);

    let found = statuses(&repo);

    assert_eq!(found["elsewhere.txt"], tracked(Change::Renamed, Change::Unchanged));
    assert_eq!(found["moved.txt"], tracked(Change::Renamed, Change::Unchanged));
}

#[test]
fn reads_a_path_with_spaces_and_quotes_in_it() {
    let fixture = Fixture::new();
    let repo = fixture.repository("awkward");
    let name = r#"a "quoted" name.txt"#;
    write(repo.join(name), "x");

    assert_eq!(statuses(&repo)[name], PathStatus::Untracked);
}

#[test]
fn reports_a_conflict_as_unmerged() {
    let fixture = Fixture::new();
    let repo = fixture.repository("conflict");
    fixture.git(&["checkout", "-q", "-b", "other"], &repo);
    write(repo.join("README.md"), "other");
    fixture.git(&["commit", "-qam", "other"], &repo);
    fixture.git(&["checkout", "-q", "main"], &repo);
    write(repo.join("README.md"), "main");
    fixture.git(&["commit", "-qam", "main"], &repo);
    let merge = std::process::Command::new("git")
        .args(["merge", "other"])
        .current_dir(&repo)
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .output()
        .unwrap();
    assert!(!merge.status.success());

    assert_eq!(statuses(&repo)["README.md"], PathStatus::Unmerged);
}

#[test]
fn is_empty_outside_a_repository() {
    let fixture = Fixture::new();
    let plain = fixture.directory("plain-status");
    write(plain.join("a.log"), "x");

    assert!(statuses(&plain).is_empty());
}

#[test]
fn a_clean_repository_has_no_entries() {
    let fixture = Fixture::new();
    assert!(statuses(&fixture.repository("clean")).is_empty());
}
