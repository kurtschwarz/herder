//! The diff and history scenarios of the app's old `LiveGitClient` tests
//! (`changeSummary`, `mergeBase`, `upstream`, `shortstat`, `changedFiles`,
//! `refs`, `recentCommits`, `commit`, `contents`), run against the daemon.

mod common;

use common::Fixture;
use herderd::git;
use herderd::protocol::{
    ChangeSummary, ChangedFile, Commit, FileChange, GitOp, GitResult, Ref, RefKind,
};
use std::fs;
use std::path::Path;

fn ask(op: GitOp) -> GitResult {
    git::handle(&op).expect("git answers")
}

fn s(path: &Path) -> String {
    path.to_str().unwrap().into()
}

fn write(path: impl AsRef<Path>, contents: impl AsRef<[u8]>) {
    let path = path.as_ref();
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, contents).unwrap();
}

fn summary(result: GitResult) -> Option<ChangeSummary> {
    match result {
        GitResult::Summary { summary } => summary,
        other => panic!("unexpected answer: {other:?}"),
    }
}

fn change_summary(at: &Path) -> Option<ChangeSummary> {
    summary(ask(GitOp::ChangeSummary { path: s(at) }))
}

fn merge_base(at: &Path, reference: &str) -> Option<String> {
    match ask(GitOp::MergeBase { path: s(at), reference: reference.into() }) {
        GitResult::MergeBase { sha } => sha,
        other => panic!("unexpected answer: {other:?}"),
    }
}

fn upstream(at: &Path) -> Option<String> {
    match ask(GitOp::Upstream { path: s(at) }) {
        GitResult::Upstream { upstream } => upstream,
        other => panic!("unexpected answer: {other:?}"),
    }
}

fn changed_files(at: &Path, since: &str) -> Vec<ChangedFile> {
    match ask(GitOp::ChangedFiles { path: s(at), since: since.into() }) {
        GitResult::ChangedFiles { files } => files,
        other => panic!("unexpected answer: {other:?}"),
    }
}

fn refs(at: &Path) -> Vec<Ref> {
    match ask(GitOp::Refs { path: s(at) }) {
        GitResult::Refs { refs } => refs,
        other => panic!("unexpected answer: {other:?}"),
    }
}

fn recent_commits(at: &Path, limit: usize) -> Vec<Commit> {
    match ask(GitOp::RecentCommits { path: s(at), limit }) {
        GitResult::Commits { commits } => commits,
        other => panic!("unexpected answer: {other:?}"),
    }
}

fn commit(at: &Path, revision: &str) -> Option<Commit> {
    match ask(GitOp::Commit { path: s(at), revision: revision.into() }) {
        GitResult::Commit { commit } => commit,
        other => panic!("unexpected answer: {other:?}"),
    }
}

fn contents(at: &Path, file: &Path, revision: &str) -> Option<String> {
    match ask(GitOp::Contents { path: s(at), file: s(file), revision: revision.into() }) {
        GitResult::Contents { text } => text,
        other => panic!("unexpected answer: {other:?}"),
    }
}

fn rev_parse(fixture: &Fixture, repo: &Path, name: &str) -> String {
    fixture.git(&["rev-parse", name], repo).trim().to_string()
}

// MARK: - contents

#[test]
fn contents_are_the_committed_text_not_the_working_or_staged_one() {
    let fixture = Fixture::new();
    let repo = fixture.repository("committed");
    let file = repo.join("sub/file.txt");
    write(&file, "committed\n");
    fixture.git(&["add", "."], &repo);
    fixture.git(&["commit", "-m", "second"], &repo);
    write(&file, "staged\n");
    fixture.git(&["add", "."], &repo);
    write(&file, "working\n");

    assert_eq!(contents(&repo, &file, "HEAD"), Some("committed\n".into()));
}

#[test]
fn contents_are_none_for_a_file_not_in_the_revision() {
    let fixture = Fixture::new();
    let repo = fixture.repository("not-committed");
    write(repo.join("new.txt"), "new\n");
    fixture.git(&["add", "new.txt"], &repo);

    assert_eq!(contents(&repo, &repo.join("new.txt"), "HEAD"), None);
    assert_eq!(contents(&repo, &repo.join("nope.txt"), "HEAD"), None);
}

#[test]
fn contents_are_none_for_a_file_that_is_not_utf8() {
    let fixture = Fixture::new();
    let repo = fixture.repository("binary");
    write(repo.join("blob.bin"), [0xFF, 0xFE, 0x00, 0x80]);
    fixture.git(&["add", "."], &repo);
    fixture.git(&["commit", "-m", "binary"], &repo);

    assert_eq!(contents(&repo, &repo.join("blob.bin"), "HEAD"), None);
}

#[test]
fn contents_are_none_outside_a_repository_or_outside_the_working_tree() {
    let fixture = Fixture::new();
    let plain = fixture.directory("plain-contents");
    write(plain.join("a.txt"), "x");
    assert_eq!(contents(&plain, &plain.join("a.txt"), "HEAD"), None);

    let repo = fixture.repository("repo");
    assert_eq!(contents(&repo, &plain.join("a.txt"), "HEAD"), None);
}

#[test]
fn contents_of_a_file_deleted_from_the_working_tree_are_still_the_committed_text() {
    let fixture = Fixture::new();
    let repo = fixture.repository("deleted");
    fs::remove_file(repo.join("README.md")).unwrap();

    assert_eq!(contents(&repo, &repo.join("README.md"), "HEAD"), Some("x".into()));
}

// MARK: - change_summary

#[test]
fn change_summary_counts_committed_and_uncommitted_lines_against_the_merge_base() {
    let fixture = Fixture::new();
    let repo = fixture.repository("changes");
    fixture.git(&["checkout", "-b", "feature"], &repo);
    write(repo.join("README.md"), "x\na\nb\n");
    fixture.git(&["commit", "-am", "more"], &repo);
    // Main moves on after the fork, which the merge-base ignores.
    fixture.git(&["checkout", "main"], &repo);
    write(repo.join("other.txt"), "x\nmain only\n");
    fixture.git(&["add", "."], &repo);
    fixture.git(&["commit", "-m", "main moves"], &repo);
    fixture.git(&["checkout", "feature"], &repo);
    // Staged and unstaged, both tracked.
    write(repo.join("README.md"), "a\nb\nc\nd\n");
    write(repo.join("added.txt"), "new\n");
    fixture.git(&["add", "added.txt"], &repo);
    // Untracked: not counted.
    write(repo.join("untracked.txt"), "ignored\nby\nthe\ncount\n");

    // README: x -> a b c d is 4 inserted, 1 deleted; added.txt: 1 inserted.
    assert_eq!(change_summary(&repo), Some(ChangeSummary { insertions: 5, deletions: 1 }));
}

#[test]
fn change_summary_falls_back_to_master() {
    let fixture = Fixture::new();
    let repo = fixture.directory("master-repo");
    fixture.git(&["init", "--initial-branch=master"], &repo);
    fixture.commit_something_as_tester(&repo);
    write(repo.join("README.md"), "x\ny\n");

    assert_eq!(change_summary(&repo), Some(ChangeSummary { insertions: 2, deletions: 1 }));
}

#[test]
fn change_summary_is_none_without_a_default_branch() {
    let fixture = Fixture::new();
    let repo = fixture.directory("trunk-repo");
    fixture.git(&["init", "--initial-branch=trunk"], &repo);
    fixture.commit_something_as_tester(&repo);

    assert_eq!(change_summary(&repo), None);
}

#[test]
fn change_summary_is_none_outside_a_worktree() {
    let fixture = Fixture::new();
    assert_eq!(change_summary(&fixture.directory("plain-changes")), None);
}

// MARK: - merge_base and upstream

#[test]
fn merge_base_of_an_ancestor_is_the_ancestor_and_of_nothing_is_none() {
    let fixture = Fixture::new();
    let repo = fixture.repository("merge-base");
    write(repo.join("README.md"), "x\na\n");
    fixture.git(&["commit", "-am", "second"], &repo);
    let first = rev_parse(&fixture, &repo, "HEAD~1");

    assert_eq!(merge_base(&repo, "HEAD~1"), Some(first));
    assert_eq!(merge_base(&repo, "nope"), None);
    assert_eq!(merge_base(&repo, "--output=x"), None);
}

#[test]
fn upstream_is_what_the_branch_tracks_else_the_default_branch() {
    let fixture = Fixture::new();
    let origin = fixture.repository("origin");
    fixture.git(&["branch", "release"], &origin);
    let clone = fixture.root().join("clone");
    fixture.git(&["clone", s(&origin).as_str(), s(&clone).as_str()], &fixture.root());
    fixture.git(&["checkout", "-b", "local-only"], &clone);

    // Tracks nothing: the default branch, which here is `origin/main`.
    assert_eq!(upstream(&clone), Some("origin/main".into()));

    fixture.git(&["checkout", "--track", "origin/release"], &clone);
    assert_eq!(upstream(&clone), Some("origin/release".into()));

    let lone = fixture.repository("lone");
    assert_eq!(upstream(&lone), Some("main".into()));
    fixture.git(&["checkout", "-b", "trunk-only"], &lone);
    fixture.git(&["branch", "-D", "main"], &lone);
    assert_eq!(upstream(&lone), None);
}

// MARK: - shortstat and changed_files

#[test]
fn shortstat_counts_staged_and_unstaged_since_a_commit() {
    let fixture = Fixture::new();
    let repo = fixture.repository("shortstat");
    write(repo.join("README.md"), "a\nb\n");
    write(repo.join("added.txt"), "new\n");
    fixture.git(&["add", "added.txt"], &repo);

    assert_eq!(
        summary(ask(GitOp::Shortstat { path: s(&repo), since: "HEAD".into() })),
        Some(ChangeSummary { insertions: 3, deletions: 1 })
    );
    assert_eq!(summary(ask(GitOp::Shortstat { path: s(&repo), since: "nope".into() })), None);
}

#[test]
fn changed_files_list_tracked_changes_with_counts_and_leave_untracked_out() {
    let fixture = Fixture::new();
    let repo = fixture.repository("changed-files");
    write(repo.join("README.md"), "a\nb\nc\n");
    write(repo.join("added.txt"), "new\n");
    fixture.git(&["add", "added.txt"], &repo);
    write(repo.join("untracked.txt"), "loose\n");

    let files = changed_files(&repo, "HEAD");

    assert_eq!(
        files.iter().map(|f| f.path.as_str()).collect::<Vec<_>>(),
        ["added.txt", "README.md"]
    );
    assert_eq!(
        files.iter().map(|f| f.status).collect::<Vec<_>>(),
        [FileChange::Added, FileChange::Modified]
    );
    assert_eq!(files[0].insertions, 1);
}

#[test]
fn changed_files_pair_a_rename_with_where_it_came_from() {
    let fixture = Fixture::new();
    let repo = fixture.repository("renamed");
    write(repo.join("moved.txt"), "something else entirely\nwith two lines\n");
    fixture.git(&["add", "."], &repo);
    fixture.git(&["commit", "-m", "second"], &repo);
    fixture.git(&["mv", "moved.txt", "elsewhere.txt"], &repo);

    let files = changed_files(&repo, "HEAD");

    assert_eq!(files.len(), 1);
    assert_eq!(files[0].path, "elsewhere.txt");
    assert_eq!(files[0].previous_path.as_deref(), Some("moved.txt"));
    assert_eq!(files[0].status, FileChange::Renamed);
}

// MARK: - refs and commits

#[test]
fn refs_and_commits_are_listed_and_a_sha_abbreviation_resolves() {
    let fixture = Fixture::new();
    let repo = fixture.repository("refs");
    fixture.git(&["tag", "v1"], &repo);
    fixture.git(&["branch", "other"], &repo);
    let sha = rev_parse(&fixture, &repo, "HEAD");

    let found = refs(&repo);
    let mut names: Vec<_> = found.iter().map(|r| r.name.as_str()).collect();
    names.sort();
    assert_eq!(names, ["main", "other", "v1"]);
    assert_eq!(found.iter().find(|r| r.name == "v1").unwrap().kind, RefKind::Tag);

    let commits = recent_commits(&repo, 5);
    assert_eq!(commits.iter().map(|c| c.sha.as_str()).collect::<Vec<_>>(), [sha.as_str()]);
    assert_eq!(commits[0].subject, "first");
    assert_eq!(commit(&repo, &sha[..7]).map(|c| c.sha), Some(sha.clone()));
    assert_eq!(commit(&repo, "feedbeef"), None);
    assert_eq!(commit(&repo, "--all"), None);
}

#[test]
fn refs_are_newest_first_and_leave_a_remotes_head_out() {
    let fixture = Fixture::new();
    let origin = fixture.repository("origin");
    let clone = fixture.root().join("clone");
    fixture.git(&["clone", s(&origin).as_str(), s(&clone).as_str()], &fixture.root());

    let names: Vec<_> = refs(&clone).into_iter().map(|r| (r.name, r.kind)).collect();

    assert!(names.contains(&("origin/main".to_string(), RefKind::RemoteBranch)));
    assert!(!names.iter().any(|(name, _)| name.ends_with("/HEAD")));
}

#[test]
fn recent_commits_stop_at_the_limit_and_are_empty_before_the_first_commit() {
    let fixture = Fixture::new();
    let repo = fixture.repository("log");
    for n in 0..3 {
        write(repo.join("README.md"), format!("{n}"));
        fixture.git(&["commit", "-am", &format!("change {n}")], &repo);
    }

    let commits = recent_commits(&repo, 2);
    assert_eq!(
        commits.iter().map(|c| c.subject.as_str()).collect::<Vec<_>>(),
        ["change 2", "change 1"]
    );

    let fresh = fixture.directory("fresh");
    fixture.git(&["init"], &fresh);
    assert!(recent_commits(&fresh, 5).is_empty());
    assert!(refs(&fresh).is_empty());
}

#[test]
fn nothing_here_answers_outside_a_working_tree() {
    let fixture = Fixture::new();
    let plain = fixture.directory("plain");
    assert!(refs(&plain).is_empty());
    assert!(recent_commits(&plain, 5).is_empty());
    assert_eq!(commit(&plain, "HEAD"), None);
    assert_eq!(upstream(&plain), None);
    assert_eq!(merge_base(&plain, "HEAD"), None);
    assert!(changed_files(&plain, "HEAD").is_empty());
}

#[test]
fn origin_head_comes_first_and_one_that_does_not_exist_is_skipped() {
    let fixture = Fixture::new();
    let origin = fixture.directory("origin");
    fixture.git(&["init", "--initial-branch=trunk"], &origin);
    fixture.commit_something_as_tester(&origin);
    let clone = fixture.root().join("clone");
    fixture.git(&["clone", s(&origin).as_str(), s(&clone).as_str()], &fixture.root());
    fixture.git(&["checkout", "-b", "feature"], &clone);

    assert_eq!(upstream(&clone), Some("origin/trunk".into()));

    // `origin/HEAD` still names it, but it no longer exists.
    fixture.git(&["update-ref", "-d", "refs/remotes/origin/trunk"], &clone);
    assert_eq!(upstream(&clone), None);
    fixture.git(&["branch", "main"], &clone);
    assert_eq!(upstream(&clone), Some("main".into()));
}

#[test]
fn refs_are_sorted_newest_tip_first() {
    let fixture = Fixture::new();
    let repo = fixture.repository("dated");
    fixture.git(&["checkout", "-b", "old"], &repo);
    write(repo.join("README.md"), "old");
    fixture.git_at(&["commit", "-am", "old"], &repo, "2001-01-01T00:00:00Z");
    fixture.git(&["checkout", "main"], &repo);

    let names: Vec<_> = refs(&repo).into_iter().map(|r| r.name).collect();

    assert_eq!(names, ["main", "old"]);
}

#[test]
fn a_subject_that_holds_separators_is_kept_whole() {
    let fixture = Fixture::new();
    let repo = fixture.repository("subject");
    write(repo.join("README.md"), "y");
    fixture.git(&["commit", "-am", "fix: a\tb | c"], &repo);

    assert_eq!(recent_commits(&repo, 1)[0].subject, "fix: a\tb | c");
}
