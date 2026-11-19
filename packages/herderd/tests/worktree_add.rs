//! The `addWorktree` scenarios of the app's old `LiveGitClient` tests, run
//! against the daemon, which adds worktrees with `gix`. The real `git` checks
//! what it wrote.

mod common;

use common::Fixture;
use herderd::git;
use herderd::protocol::{Checkout, GitErrorCode, GitOp, GitResult};
use std::fs;
use std::path::Path;

fn add(
    repo: &Path,
    worktree: &Path,
    branch: &str,
    base: &str,
    exclude: Option<&str>,
) -> Result<GitResult, herderd::protocol::GitError> {
    git::handle(&GitOp::AddWorktree {
        path: repo.to_str().unwrap().into(),
        worktree: worktree.to_str().unwrap().into(),
        new_branch: branch.into(),
        base: base.into(),
        exclude: exclude.map(String::from),
    })
}

fn checkouts(repo: &Path) -> Vec<Checkout> {
    let op = GitOp::Worktrees { path: repo.to_str().unwrap().into() };
    match git::handle(&op).unwrap() {
        GitResult::Worktrees { worktrees } => worktrees.into_iter().map(|t| t.checkout).collect(),
        other => panic!("unexpected answer: {other:?}"),
    }
}

fn branch(name: &str) -> Checkout {
    Checkout::Branch { name: name.into() }
}

fn exclude_lines(repo: &Path) -> Vec<String> {
    fs::read_to_string(repo.join(".git/info/exclude")).unwrap().lines().map(String::from).collect()
}

#[test]
fn adding_a_worktree_creates_it_on_a_new_branch() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");
    let path = repo.join("agent/add-minimap");

    add(&repo, &path, "agent/add-minimap", "main", Some("agent")).unwrap();

    assert_eq!(checkouts(&repo), [branch("main"), branch("agent/add-minimap")]);
    assert!(path.join("README.md").exists());
}

#[test]
fn a_nested_worktree_excludes_the_folder_it_sits_in() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");

    add(&repo, &repo.join("agent/add-minimap"), "agent/add-minimap", "main", Some("agent"))
        .unwrap();

    assert!(fixture.git(&["status", "--porcelain"], &repo).is_empty());
    // The folder git made for the branch family, not the worktree itself.
    assert!(exclude_lines(&repo).contains(&"/agent/".to_string()));
}

#[test]
fn the_worktree_folder_stays_out_of_git_status() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");

    add(&repo, &repo.join("feature"), "feature", "main", Some("feature")).unwrap();
    add(&repo, &repo.join("other"), "other", "main", Some("other")).unwrap();

    assert!(fixture.git(&["status", "--porcelain"], &repo).is_empty());
    let lines = exclude_lines(&repo);
    assert_eq!(lines.iter().filter(|line| *line == "/feature/" || *line == "/other/").count(), 2);
}

#[test]
fn excluding_a_folder_twice_writes_it_once() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");

    add(&repo, &repo.join("a/one"), "a/one", "main", Some("a")).unwrap();
    add(&repo, &repo.join("a/two"), "a/two", "main", Some("a")).unwrap();

    assert_eq!(exclude_lines(&repo).iter().filter(|line| *line == "/a/").count(), 1);
}

#[test]
fn adding_to_a_bare_repository_puts_the_worktree_beside_the_rest() {
    let fixture = Fixture::new();
    let bare = fixture.directory("origin.git");
    fixture.git(&["init", "--bare", "--initial-branch=main"], &bare);
    fixture.seed("origin", &bare);

    add(&bare, &bare.join("feature"), "feature", "main", Some("feature")).unwrap();

    assert_eq!(checkouts(&bare), [branch("feature")]);
    // A bare repository has no working tree to keep clean, so no exclude file
    // gains an entry.
    let exclude = fs::read_to_string(bare.join("info/exclude")).unwrap_or_default();
    assert!(!exclude.contains("/feature/"));
}

#[test]
fn adding_to_a_project_whose_dot_git_is_bare_creates_a_sibling_and_leaves_the_exclude_file_alone() {
    let fixture = Fixture::new();
    let project = fixture.project_with_bare_dot_git("project");

    add(&project, &project.join("feature"), "feature", "main", Some("feature")).unwrap();

    assert_eq!(checkouts(&project), [branch("feature"), branch("main")]);
    let exclude = fs::read_to_string(project.join(".git/info/exclude")).unwrap_or_default();
    assert!(!exclude.contains("/feature/"));
}

#[test]
fn adding_to_a_dot_bare_layout_creates_a_folder_beside_the_others() {
    let fixture = Fixture::new();
    let project = fixture.bare_layout("project");

    add(&project, &project.join("feature"), "feature", "main", Some("feature")).unwrap();

    assert_eq!(checkouts(&project), [branch("feature"), branch("main")]);
}

#[test]
fn a_branch_that_already_exists_is_refused() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");

    let error = add(&repo, &repo.join("main"), "main", "main", None).unwrap_err();

    assert_eq!(error.code, GitErrorCode::Failed);
    assert!(error.message.contains("already exists"), "{}", error.message);
}

#[test]
fn a_branch_that_reads_as_an_option_is_refused() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");

    let error = add(&repo, &repo.join("x"), "--force", "main", None).unwrap_err();

    assert_eq!(error.code, GitErrorCode::InvalidRequest);
    assert!(!repo.join("x").exists());
}

#[test]
fn git_sees_a_clean_worktree_on_the_new_branch_at_the_base_commit() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");
    write_commit(&fixture, &repo, "second");
    let base = fixture.git(&["rev-parse", "HEAD~1"], &repo);
    let path = fixture.root().join("feature");

    add(&repo, &path, "feature", "HEAD~1", None).unwrap();

    assert_eq!(fixture.git(&["rev-parse", "HEAD"], &path), base);
    assert_eq!(fixture.git(&["branch", "--show-current"], &path).trim(), "feature");
    assert!(fixture.git(&["status", "--porcelain"], &path).is_empty());
    assert!(fixture.git(&["worktree", "list"], &repo).contains("[feature]"));
    // Both refs were logged, as `git worktree add -b` logs them.
    assert!(!fixture.git(&["reflog", "show", "feature"], &repo).is_empty());
    assert!(!fixture.git(&["reflog", "show", "HEAD"], &path).is_empty());
}

#[test]
fn a_base_that_names_nothing_is_refused_and_makes_no_branch() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");

    let error = add(&repo, &repo.join("x"), "x", "nope", None).unwrap_err();

    assert_eq!(error.code, GitErrorCode::Failed);
    assert!(fixture.git(&["branch", "--list", "x"], &repo).is_empty());
    assert!(!repo.join("x").exists());
}

#[test]
fn a_destination_that_is_not_empty_is_refused_and_makes_no_branch() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");
    let path = fixture.directory("occupied");
    fs::write(path.join("keep.txt"), "x").unwrap();

    let error = add(&repo, &path, "occupied", "main", None).unwrap_err();

    assert_eq!(error.code, GitErrorCode::Failed);
    assert!(error.message.contains("already exists"), "{}", error.message);
    assert!(fixture.git(&["branch", "--list", "occupied"], &repo).is_empty());
    assert!(path.join("keep.txt").exists());
}

#[test]
fn a_path_registered_to_another_worktree_is_refused_and_its_branch_removed() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");
    let path = fixture.root().join("gone");
    add(&repo, &path, "first", "main", None).unwrap();
    // Deleted on disk but still registered until pruned.
    fs::remove_dir_all(&path).unwrap();

    assert!(add(&repo, &path, "second", "main", None).is_err());
    assert!(fixture.git(&["branch", "--list", "second"], &repo).is_empty());
}

fn write_commit(fixture: &Fixture, repo: &Path, message: &str) {
    fs::write(repo.join("README.md"), message).unwrap();
    fixture.git(&["commit", "-qam", message], repo);
}
