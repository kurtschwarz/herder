#![allow(dead_code)] // Each test crate uses its own subset.
//! Repositories built with the real `git` CLI, so the expected answers come
//! from git itself and not from the same code the daemon uses to read them.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use tempfile::TempDir;

pub struct Fixture {
    dir: TempDir,
}

impl Fixture {
    pub fn new() -> Self {
        Fixture { dir: tempfile::tempdir().expect("temporary directory") }
    }

    /// The fixture's own folder, resolved, because macOS temp folders sit
    /// behind a symlink and the daemon answers with resolved paths.
    pub fn root(&self) -> PathBuf {
        fs::canonicalize(self.dir.path()).unwrap()
    }

    pub fn directory(&self, name: &str) -> PathBuf {
        let path = self.root().join(name);
        fs::create_dir_all(&path).unwrap();
        path
    }

    pub fn git(&self, args: &[&str], in_dir: &Path) -> String {
        let output = Command::new("git")
            .args(args)
            .current_dir(in_dir)
            // A developer's own config may sign commits or rewrite refs.
            .env("GIT_CONFIG_GLOBAL", "/dev/null")
            .env("GIT_CONFIG_SYSTEM", "/dev/null")
            .env("GIT_TERMINAL_PROMPT", "0")
            .output()
            .expect("git runs");
        assert!(
            output.status.success(),
            "git {} failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&output.stderr)
        );
        String::from_utf8_lossy(&output.stdout).into_owned()
    }

    fn identify(&self, repo: &Path) {
        self.git(&["config", "user.email", "test@example.com"], repo);
        self.git(&["config", "user.name", "Test"], repo);
        self.git(&["config", "commit.gpgsign", "false"], repo);
    }

    pub fn commit_something(&self, repo: &Path) {
        fs::write(repo.join("README.md"), "x").unwrap();
        self.git(&["add", "."], repo);
        self.git(&["commit", "-m", "first"], repo);
    }

    /// A repository with one commit on `main`.
    pub fn repository(&self, name: &str) -> PathBuf {
        let path = self.directory(name);
        self.git(&["init", "--initial-branch=main"], &path);
        self.identify(&path);
        self.commit_something(&path);
        path
    }

    /// Puts one commit on `main` of the bare repository at `bare`, through a
    /// throwaway clone.
    pub fn seed(&self, name: &str, bare: &Path) {
        let seed = self.directory(&format!("seed-{name}"));
        self.git(&["clone", bare.to_str().unwrap(), seed.to_str().unwrap()], &self.root());
        self.identify(&seed);
        self.commit_something(&seed);
        self.git(&["push", "origin", "main"], &seed);
    }

    /// A project folder whose `.git` is a bare repository, with a worktree
    /// `main` beside it.
    pub fn project_with_bare_dot_git(&self, name: &str) -> PathBuf {
        let project = self.directory(name);
        let dot_git = project.join(".git");
        fs::create_dir_all(&dot_git).unwrap();
        self.git(&["init", "--bare", "--initial-branch=main"], &dot_git);
        self.seed(name, &dot_git);
        self.git(&["worktree", "add", "main", "main"], &project);
        project
    }

    /// The `.bare` convention: internals in `.bare`, a `.git` file naming it,
    /// and a worktree `main` beside them.
    pub fn bare_layout(&self, name: &str) -> PathBuf {
        let project = self.directory(name);
        let bare = project.join(".bare");
        fs::create_dir_all(&bare).unwrap();
        self.git(&["init", "--bare", "--initial-branch=main"], &bare);
        fs::write(project.join(".git"), "gitdir: ./.bare\n").unwrap();
        self.seed(name, &bare);
        self.git(&["worktree", "add", "main", "main"], &project);
        project
    }
}
