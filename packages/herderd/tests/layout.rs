//! The `worktrees`, `branches`, `git_directory` and `checkout` scenarios of the
//! app's old `LiveGitClient` tests, run against the daemon.

mod common;

use common::Fixture;
use herderd::git;
use herderd::protocol::{Checkout, GitOp, GitResult, Worktree};
use std::fs;
use std::path::{Path, PathBuf};

fn ask(op: GitOp) -> GitResult {
    git::handle(&op).expect("git answers")
}

fn path(path: &Path) -> String {
    path.to_str().unwrap().into()
}

fn worktrees(at: &Path) -> Vec<Worktree> {
    match ask(GitOp::Worktrees { path: path(at) }) {
        GitResult::Worktrees { worktrees } => worktrees,
        other => panic!("unexpected answer: {other:?}"),
    }
}

fn branches(at: &Path) -> Vec<String> {
    match ask(GitOp::Branches { path: path(at) }) {
        GitResult::Branches { branches } => branches,
        other => panic!("unexpected answer: {other:?}"),
    }
}

fn git_directory(of: &Path) -> Option<String> {
    match ask(GitOp::GitDirectory { path: path(of) }) {
        GitResult::GitDirectory { path } => path,
        other => panic!("unexpected answer: {other:?}"),
    }
}

fn checkout(of: &Path) -> Option<Checkout> {
    match ask(GitOp::Checkout { path: path(of) }) {
        GitResult::Checkout { checkout } => checkout,
        other => panic!("unexpected answer: {other:?}"),
    }
}

fn branch(name: &str) -> Checkout {
    Checkout::Branch { name: name.into() }
}

fn checkouts(trees: &[Worktree]) -> Vec<&Checkout> {
    trees.iter().map(|tree| &tree.checkout).collect()
}

fn add_worktree(fixture: &Fixture, repo: &Path, name: &str) -> PathBuf {
    let tree = fixture.root().join(name);
    fixture.git(&["worktree", "add", tree.to_str().unwrap(), "-b", name], repo);
    tree
}

// MARK: - worktrees

#[test]
fn repository_without_worktrees_lists_only_its_main_working_tree() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");

    let trees = worktrees(&repo);

    assert_eq!(trees.len(), 1);
    assert_eq!(trees[0].path, path(&repo));
    assert_eq!(trees[0].checkout, branch("main"));
    assert!(trees[0].is_main_working_tree);
    assert_eq!(trees[0].host, herderd::protocol::HostId::local());
}

#[test]
fn worktrees_report_when_they_last_changed() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");
    add_worktree(&fixture, &repo, "feature");

    let now =
        std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64();
    for tree in worktrees(&repo) {
        let activity = tree.last_activity.expect("a last activity");
        assert!((now - activity).abs() < 120.0);
    }
}

#[test]
fn linked_worktrees_follow_main_and_sort_by_branch() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");
    for name in ["zeta", "alpha"] {
        add_worktree(&fixture, &repo, name);
    }

    let trees = worktrees(&repo);

    assert_eq!(checkouts(&trees), [&branch("main"), &branch("alpha"), &branch("zeta")]);
    assert_eq!(
        trees.iter().map(|tree| tree.is_main_working_tree).collect::<Vec<_>>(),
        [true, false, false]
    );
    assert_eq!(trees[1].path, path(&fixture.root().join("alpha")));
}

#[test]
fn detached_worktree_shows_short_sha_and_sorts_last() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");
    let detached = fixture.root().join("detached");
    fixture.git(&["worktree", "add", "--detach", detached.to_str().unwrap()], &repo);
    add_worktree(&fixture, &repo, "beta");

    let sha = fixture.git(&["rev-parse", "--short=7", "HEAD"], &repo).trim().to_string();
    let trees = worktrees(&repo);

    assert_eq!(checkouts(&trees), [&branch("main"), &branch("beta"), &Checkout::Detached { sha }]);
}

#[test]
fn bare_repository_contributes_only_its_worktrees() {
    let fixture = Fixture::new();
    let bare = fixture.directory("origin.git");
    fixture.git(&["init", "--bare", "--initial-branch=main"], &bare);
    fixture.seed("origin", &bare);
    let tree = fixture.root().join("bare-main");
    fixture.git(&["worktree", "add", tree.to_str().unwrap(), "main"], &bare);

    let trees = worktrees(&bare);

    assert_eq!(trees.len(), 1);
    assert_eq!(trees[0].checkout, branch("main"));
    assert!(!trees[0].is_main_working_tree);
}

#[test]
fn worktree_whose_folder_was_deleted_is_skipped() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");
    let gone = add_worktree(&fixture, &repo, "gone");
    fs::remove_dir_all(gone).unwrap();

    assert_eq!(checkouts(&worktrees(&repo)), [&branch("main")]);
}

#[test]
fn non_repositories_and_linked_worktrees_have_no_worktrees() {
    let fixture = Fixture::new();
    assert!(worktrees(&fixture.directory("plain")).is_empty());

    let repo = fixture.repository("repo");
    let linked = add_worktree(&fixture, &repo, "linked");
    assert!(worktrees(&linked).is_empty());
}

#[test]
fn a_project_whose_dot_git_is_bare_has_the_folders_beside_dot_git() {
    let fixture = Fixture::new();
    let project = fixture.project_with_bare_dot_git("project");

    let trees = worktrees(&project);

    assert_eq!(checkouts(&trees), [&branch("main")]);
    assert_eq!(trees[0].path, path(&project.join("main")));
    assert!(!trees[0].is_main_working_tree);
    assert_eq!(branches(&project), ["main"]);
}

#[test]
fn a_bare_layout_has_the_folders_beside_the_bare_directory() {
    let fixture = Fixture::new();
    let project = fixture.bare_layout("project");

    let trees = worktrees(&project);

    assert_eq!(checkouts(&trees), [&branch("main")]);
    assert_eq!(trees[0].path, path(&project.join("main")));
    assert!(!trees[0].is_main_working_tree);
    assert_eq!(branches(&project), ["main"]);
}

#[test]
fn a_worktree_added_beside_the_others_is_listed() {
    let fixture = Fixture::new();
    let project = fixture.bare_layout("project");
    fixture.git(&["worktree", "add", "feature", "-b", "feature"], &project);

    assert_eq!(checkouts(&worktrees(&project)), [&branch("feature"), &branch("main")]);
}

// MARK: - branches

#[test]
fn lists_local_branches_including_slashed_and_packed_ones() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");
    fixture.git(&["branch", "agent/add-minimap"], &repo);
    fixture.git(&["branch", "zeta"], &repo);
    fixture.git(&["pack-refs", "--all"], &repo);
    fixture.git(&["branch", "alpha"], &repo);

    assert_eq!(branches(&repo), ["agent/add-minimap", "alpha", "main", "zeta"]);
}

#[test]
fn a_bare_repository_lists_its_branches() {
    let fixture = Fixture::new();
    let bare = fixture.directory("origin.git");
    fixture.git(&["init", "--bare", "--initial-branch=main"], &bare);
    fixture.seed("origin", &bare);

    assert_eq!(branches(&bare), ["main"]);
}

#[test]
fn non_repositories_and_linked_worktrees_have_no_branch_list() {
    let fixture = Fixture::new();
    assert!(branches(&fixture.directory("plain")).is_empty());

    let repo = fixture.repository("repo");
    let linked = add_worktree(&fixture, &repo, "linked");
    assert!(branches(&linked).is_empty());
}

// MARK: - git_directory and checkout

#[test]
fn a_working_trees_git_directory_is_its_dot_git() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");
    assert_eq!(git_directory(&repo), Some(path(&repo.join(".git"))));
}

#[test]
fn a_linked_worktrees_git_directory_is_inside_the_main_repository() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");
    let linked = add_worktree(&fixture, &repo, "linked");
    assert_eq!(git_directory(&linked), Some(path(&repo.join(".git/worktrees/linked"))));
}

#[test]
fn folders_that_are_not_working_trees_have_no_git_directory_or_checkout() {
    let fixture = Fixture::new();
    let plain = fixture.directory("plain");
    let bare = fixture.directory("origin.git");
    fixture.git(&["init", "--bare"], &bare);
    let project = fixture.bare_layout("project");

    for folder in [&plain, &bare, &project, &fixture.root().join("missing")] {
        assert_eq!(git_directory(folder), None, "{folder:?}");
        assert_eq!(checkout(folder), None, "{folder:?}");
    }
}

#[test]
fn checkout_is_the_branch_or_the_short_commit_when_detached() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");
    assert_eq!(checkout(&repo), Some(branch("main")));

    let detached = fixture.root().join("detached");
    fixture.git(&["worktree", "add", "--detach", detached.to_str().unwrap()], &repo);
    let sha = fixture.git(&["rev-parse", "--short=7", "HEAD"], &repo).trim().to_string();
    assert_eq!(checkout(&detached), Some(Checkout::Detached { sha }));
}

#[test]
fn a_repository_with_no_commit_yet_is_on_its_unborn_branch() {
    let fixture = Fixture::new();
    let repo = fixture.directory("fresh");
    fixture.git(&["init", "--initial-branch=trunk"], &repo);
    assert_eq!(checkout(&repo), Some(branch("trunk")));
}
