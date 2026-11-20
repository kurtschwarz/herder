//! Which GitHub repository a folder's `origin` points at.

use super::kind;

/// The owner and name `origin` names, when it is a github.com remote. `None`
/// for any other host, for a folder with no `origin`, and for one that is not
/// a repository root: none of those is an error, only a repository there is
/// nothing to ask GitHub about.
pub fn github_repository(path: &str) -> Option<(String, String)> {
    let opened = kind::open(path)?;
    let url = opened.repo.config_snapshot().string("remote.origin.url")?;
    parse_github_url(&url.to_string())
}

/// Reads the owner and name out of the forms `git clone` accepts for
/// github.com: `https://github.com/o/r(.git)`, `git@github.com:o/r(.git)` and
/// `ssh://git@github.com/o/r(.git)`.
pub fn parse_github_url(url: &str) -> Option<(String, String)> {
    let url = url.trim();
    let rest = if let Some(rest) = url.strip_prefix("git@github.com:") {
        rest
    } else {
        let (scheme, rest) = url.split_once("://")?;
        if !matches!(scheme, "https" | "http" | "ssh" | "git") {
            return None;
        }
        // Credentials and a port are not part of who the host is.
        let (authority, path) = rest.split_once('/')?;
        let host = authority.rsplit_once('@').map_or(authority, |(_, host)| host);
        let host = host.split_once(':').map_or(host, |(host, _)| host);
        if !host.eq_ignore_ascii_case("github.com") {
            return None;
        }
        path
    };

    let rest = rest.trim_matches('/');
    let rest = rest.strip_suffix(".git").unwrap_or(rest);
    let (owner, name) = rest.split_once('/')?;
    let valid = |part: &str| {
        !part.is_empty()
            && part.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
    };
    (valid(owner) && valid(name)).then(|| (owner.to_string(), name.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parsed(url: &str) -> Option<(String, String)> {
        parse_github_url(url)
    }

    fn pair(owner: &str, name: &str) -> Option<(String, String)> {
        Some((owner.into(), name.into()))
    }

    #[test]
    fn reads_the_forms_git_clone_takes() {
        assert_eq!(
            parsed("https://github.com/kurtschwarz/herder.git"),
            pair("kurtschwarz", "herder")
        );
        assert_eq!(parsed("https://github.com/kurtschwarz/herder"), pair("kurtschwarz", "herder"));
        assert_eq!(parsed("git@github.com:kurtschwarz/herder.git"), pair("kurtschwarz", "herder"));
        assert_eq!(
            parsed("ssh://git@github.com/kurtschwarz/herder.git"),
            pair("kurtschwarz", "herder")
        );
        assert_eq!(
            parsed("https://user:token@github.com/kurtschwarz/herder.git"),
            pair("kurtschwarz", "herder")
        );
    }

    #[test]
    fn a_name_with_dots_keeps_them() {
        assert_eq!(parsed("git@github.com:o/herder.rs.git"), pair("o", "herder.rs"));
    }

    #[test]
    fn other_hosts_are_not_github() {
        assert_eq!(parsed("https://gitlab.com/o/r.git"), None);
        assert_eq!(parsed("git@gitlab.com:o/r.git"), None);
        assert_eq!(parsed("https://github.com.evil.example/o/r.git"), None);
        assert_eq!(parsed("https://github.example.com/o/r.git"), None);
        assert_eq!(parsed("/some/local/path"), None);
        assert_eq!(parsed("../sibling"), None);
    }

    #[test]
    fn a_url_without_an_owner_and_name_is_not_one() {
        assert_eq!(parsed("https://github.com/"), None);
        assert_eq!(parsed("https://github.com/o"), None);
        assert_eq!(parsed("https://github.com/o/r/extra"), None);
    }
}
