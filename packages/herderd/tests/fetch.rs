//! `fetch`: bring the remote's default branch up to date and say which ref a
//! new branch should be cut from. The real `git` makes the fixtures and checks
//! what the daemon did.

mod common;

use common::Fixture;
use herderd::git;
use herderd::protocol::{GitOp, GitResult};
use std::path::Path;

fn fetch(repo: &Path) -> Option<String> {
    match git::handle(&GitOp::Fetch { path: repo.to_str().unwrap().into() }).expect("git answers") {
        GitResult::Fetched { base } => base,
        other => panic!("unexpected answer: {other:?}"),
    }
}

fn clone_of(fixture: &Fixture, origin: &Path) -> std::path::PathBuf {
    let clone = fixture.root().join("clone");
    fixture.git(&["clone", origin.to_str().unwrap(), clone.to_str().unwrap()], &fixture.root());
    clone
}

#[test]
fn fetching_brings_in_the_remote_default_branch_and_names_it() {
    let fixture = Fixture::new();
    let origin = fixture.repository("origin");
    let clone = clone_of(&fixture, &origin);
    std::fs::write(origin.join("new.txt"), "x").unwrap();
    fixture.git(&["add", "."], &origin);
    fixture.git(&["commit", "-m", "second"], &origin);
    let tip = fixture.git(&["rev-parse", "HEAD"], &origin);

    assert_eq!(fetch(&clone), Some("origin/main".into()));
    assert_eq!(fixture.git(&["rev-parse", "origin/main"], &clone), tip);
}

#[test]
fn a_remote_that_cannot_be_reached_still_names_the_existing_ref() {
    let fixture = Fixture::new();
    let origin = fixture.repository("origin");
    let clone = clone_of(&fixture, &origin);
    fixture.git(&["remote", "set-url", "origin", "/nonexistent/remote"], &clone);

    assert_eq!(fetch(&clone), Some("origin/main".into()));
}

#[test]
fn without_a_remote_the_local_default_branch_is_the_base() {
    let fixture = Fixture::new();
    let repo = fixture.repository("lone");

    assert_eq!(fetch(&repo), Some("main".into()));
}

#[test]
fn fetching_only_the_default_branch_leaves_other_branches_alone() {
    let fixture = Fixture::new();
    let origin = fixture.repository("origin");
    let clone = clone_of(&fixture, &origin);
    fixture.git(&["branch", "release"], &origin);

    fetch(&clone);

    assert!(fixture.git(&["branch", "-r"], &clone).lines().all(|line| !line.contains("release")));
}
