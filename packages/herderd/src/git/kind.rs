//! What a folder is, as far as git is concerned.

use crate::protocol::RepositoryKind;
use gix::repository::Kind;
use std::fs;
use std::path::{Path, PathBuf};

/// A folder that is a repository root, opened.
pub struct Opened {
    pub repo: gix::Repository,
    pub kind: RepositoryKind,
}

/// Only the distinctions the add-a-workspace flow acts on. A subdirectory of a
/// repository, or the `.git` directory of a working tree, is not a repository
/// root: a workspace maps to a repository, not to a folder inside one.
pub fn repository_kind(path: &str) -> RepositoryKind {
    open(path).map_or(RepositoryKind::NotARepository, |opened| opened.kind)
}

/// `None` for anything that is not a repository root.
pub fn open(path: &str) -> Option<Opened> {
    let root = fs::canonicalize(path).ok()?;
    // `open`, not `discover`: it must not walk upwards out of a subdirectory.
    let repo = gix::open_opts(&root, gix::open::Options::isolated()).ok()?;
    let kind = classify(&repo, &root);
    (kind != RepositoryKind::NotARepository).then_some(Opened { repo, kind })
}

fn classify(repo: &gix::Repository, root: &Path) -> RepositoryKind {
    let git_dir = canonical(repo.git_dir());

    // First: a worktree of a bare repository reads `core.bare` from the shared
    // config and so says it is bare too.
    if repo.kind() == Kind::LinkedWorkTree {
        return RepositoryKind::LinkedWorktree {
            main_repository: path_string(&repository_root(&canonical(repo.common_dir()))),
        };
    }

    if repo.is_bare() {
        // Either the bare directory itself or a project folder holding one
        // as `.git`; never something else that happens to open as bare.
        return if git_dir == root || root.join(".git").exists() {
            RepositoryKind::Bare
        } else {
            RepositoryKind::NotARepository
        };
    }

    match repo.kind() {
        Kind::Common => {
            // Opening a working tree's own `.git` directory also succeeds.
            match repo.workdir().map(canonical) {
                Some(workdir) if workdir == root => RepositoryKind::MainWorkingTree,
                _ => RepositoryKind::NotARepository,
            }
        }
        Kind::Submodule | Kind::LinkedWorkTree => RepositoryKind::NotARepository,
    }
}

/// The folder a user would call the repository: the working tree beside a
/// `.git` directory, or the bare directory itself. A `.git` file beside the
/// directory, naming it, means the folder holding both is the repository: the
/// `.bare` layout, where the git directory is not named `.git` at all.
fn repository_root(common: &Path) -> PathBuf {
    let Some(parent) = common.parent() else {
        return common.to_path_buf();
    };
    if common.file_name().is_some_and(|name| name == ".git") {
        return parent.to_path_buf();
    }
    let dot_git = parent.join(".git");
    if dot_git.is_file() && names(&dot_git, parent).is_some_and(|named| named == common) {
        return parent.to_path_buf();
    }
    common.to_path_buf()
}

/// The directory a `.git` file's `gitdir:` line names.
fn names(dot_git: &Path, relative_to: &Path) -> Option<PathBuf> {
    let contents = fs::read_to_string(dot_git).ok()?;
    let line = contents.lines().find_map(|line| line.strip_prefix("gitdir:"))?;
    let target = Path::new(line.trim());
    let resolved =
        if target.is_absolute() { target.to_path_buf() } else { relative_to.join(target) };
    fs::canonicalize(resolved).ok()
}

pub fn canonical(path: &Path) -> PathBuf {
    fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}

pub fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}
