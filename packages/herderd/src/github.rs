//! The daemon's one use of GitHub: asking who a token belongs to.
//!
//! The app signs in and owns the token; the daemon is handed it, keeps it in
//! memory and never writes it anywhere. Nothing here returns the token or puts
//! it in an error: a message that could quote it is built from fixed words.
//!
//! This is the only module that makes a network request. It is blocking, so
//! the caller runs it on a worker, and it takes the GraphQL endpoint as a
//! parameter so a test can point it at a stub.

use crate::protocol::{GitHubCheck, Secret};
use serde::Deserialize;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

/// Where GitHub answers GraphQL.
pub const ENDPOINT: &str = "https://api.github.com/graphql";

const VIEWER: &str = r#"{"query":"query { viewer { login } }"}"#;

/// The daemon's standing with GitHub: the token it was handed, if any.
pub struct GitHub {
    endpoint: String,
    token: Mutex<Option<Secret>>,
    agent: ureq::Agent,
}

impl GitHub {
    pub fn new(endpoint: impl Into<String>) -> Self {
        let agent = ureq::Agent::config_builder()
            // A 401 is an answer, not a failure of the request.
            .http_status_as_error(false)
            .timeout_global(Some(Duration::from_secs(20)))
            .user_agent("herderd")
            .build()
            .new_agent();
        GitHub { endpoint: endpoint.into(), token: Mutex::new(None), agent }
    }

    /// The one the running daemon uses: every connection shares it, because the
    /// app sends a token once and asks for git on connections of its own.
    pub fn shared() -> &'static GitHub {
        static SHARED: OnceLock<GitHub> = OnceLock::new();
        SHARED.get_or_init(|| GitHub::new(ENDPOINT))
    }

    pub fn set_token(&self, token: Secret) {
        if let Ok(mut held) = self.token.lock() {
            *held = Some(token);
        }
    }

    pub fn clear_token(&self) {
        if let Ok(mut held) = self.token.lock() {
            *held = None;
        }
    }

    /// Runs a `viewer` query with the token held and says what came of it.
    pub fn check(&self) -> GitHubCheck {
        let Some(token) = self.token.lock().ok().and_then(|held| held.clone()) else {
            return GitHubCheck::NotConnected;
        };

        let response = self
            .agent
            .post(&self.endpoint)
            .header("Authorization", format!("Bearer {}", token.expose()))
            .header("Content-Type", "application/json")
            .send(VIEWER);
        let mut response = match response {
            Ok(response) => response,
            // `ureq` describes what failed, never the headers it sent, but the
            // token is scrubbed anyway: this text reaches the app's screen.
            Err(error) => return failure(&token, format!("could not reach GitHub: {error}")),
        };

        match response.status().as_u16() {
            401 => return GitHubCheck::Unauthorized,
            200 => {}
            status => return failure(&token, format!("GitHub answered {status}")),
        }
        match response.body_mut().read_json::<Reply>() {
            Ok(Reply { data: Some(Data { viewer: Viewer { login } }), .. }) => {
                GitHubCheck::Ok { login }
            }
            Ok(Reply { errors, .. }) => {
                let first = errors.into_iter().flatten().next().map(|error| error.message);
                failure(&token, first.unwrap_or_else(|| "GitHub's answer had no viewer".into()))
            }
            Err(_) => failure(&token, "GitHub's answer was not one herderd understands".into()),
        }
    }
}

fn failure(token: &Secret, message: String) -> GitHubCheck {
    GitHubCheck::Error { message: message.replace(token.expose(), "<redacted>") }
}

#[derive(Deserialize)]
struct Reply {
    data: Option<Data>,
    errors: Option<Vec<GraphQlError>>,
}

#[derive(Deserialize)]
struct Data {
    viewer: Viewer,
}

#[derive(Deserialize)]
struct Viewer {
    login: String,
}

#[derive(Deserialize)]
struct GraphQlError {
    message: String,
}
