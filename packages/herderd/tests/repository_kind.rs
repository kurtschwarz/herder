//! The scenarios the app's old `LiveGitClient` tests held for
//! `repositoryKind`, run against the daemon: the contract the Swift client is
//! held to as well.

mod common;

use common::Fixture;
use herderd::git;
use herderd::protocol::{GitOp, GitResult, RepositoryKind};
use std::fs;
use std::path::Path;

fn kind(path: &Path) -> RepositoryKind {
    let op = GitOp::RepositoryKind { path: path.to_str().unwrap().into() };
    match git::handle(&op) {
        Ok(GitResult::RepositoryKind(kind)) => kind,
        other => panic!("unexpected answer: {other:?}"),
    }
}

fn linked(main_repository: &Path) -> RepositoryKind {
    RepositoryKind::LinkedWorktree { main_repository: main_repository.to_str().unwrap().into() }
}

#[test]
fn plain_folder_is_not_a_repository() {
    let fixture = Fixture::new();
    assert_eq!(kind(&fixture.directory("plain")), RepositoryKind::NotARepository);
}

#[test]
fn repository_root_is_a_main_working_tree() {
    let fixture = Fixture::new();
    assert_eq!(kind(&fixture.repository("repo")), RepositoryKind::MainWorkingTree);
}

#[test]
fn subdirectory_of_a_repository_is_not_a_repository() {
    let fixture = Fixture::new();
    let nested = fixture.repository("repo").join("src");
    fs::create_dir_all(&nested).unwrap();
    assert_eq!(kind(&nested), RepositoryKind::NotARepository);
}

#[test]
fn the_dot_git_directory_of_a_working_tree_is_refused() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");
    assert_eq!(kind(&repo.join(".git")), RepositoryKind::NotARepository);
}

#[test]
fn bare_repository_is_recognised() {
    let fixture = Fixture::new();
    let bare = fixture.directory("api.git");
    fixture.git(&["init", "--bare"], &bare);
    assert_eq!(kind(&bare), RepositoryKind::Bare);
}

#[test]
fn linked_worktree_reports_its_main_repository() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");
    let worktree = fixture.root().join("feature");
    fixture.git(&["worktree", "add", worktree.to_str().unwrap(), "-b", "feature"], &repo);
    assert_eq!(kind(&worktree), linked(&repo));
}

#[test]
fn worktree_of_a_bare_repository_reports_the_bare_directory() {
    let fixture = Fixture::new();
    let bare = fixture.directory("origin.git");
    fixture.git(&["init", "--bare", "--initial-branch=main"], &bare);
    fixture.seed("origin", &bare);
    let worktree = fixture.root().join("bare-feature");
    fixture.git(&["worktree", "add", worktree.to_str().unwrap(), "main"], &bare);
    assert_eq!(kind(&worktree), linked(&bare));
}

#[test]
fn a_project_whose_dot_git_is_bare_is_a_bare_repository() {
    let fixture = Fixture::new();
    let project = fixture.project_with_bare_dot_git("project");
    assert_eq!(kind(&project), RepositoryKind::Bare);
}

#[test]
fn a_worktree_of_it_names_the_project_folder_as_its_repository() {
    let fixture = Fixture::new();
    let project = fixture.project_with_bare_dot_git("project");
    assert_eq!(kind(&project.join("main")), linked(&project));
}

#[test]
fn a_dot_git_file_naming_a_bare_repository_is_a_bare_repository() {
    let fixture = Fixture::new();
    let project = fixture.bare_layout("project");
    assert_eq!(kind(&project), RepositoryKind::Bare);
}

#[test]
fn one_of_its_worktrees_points_back_at_the_project_folder() {
    let fixture = Fixture::new();
    let project = fixture.bare_layout("project");
    // Not `.bare`, which is where the files are, and not the worktree itself.
    assert_eq!(kind(&project.join("main")), linked(&project));
}

#[test]
fn missing_folder_is_not_a_repository() {
    let fixture = Fixture::new();
    assert_eq!(kind(&fixture.root().join("nothing-here")), RepositoryKind::NotARepository);
}
