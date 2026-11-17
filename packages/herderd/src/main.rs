use std::io;
use std::path::PathBuf;
use std::process::ExitCode;
use std::time::Duration;

const USAGE: &str = "usage: herderd --socket PATH [--idle-timeout SECONDS] | --stdio | --version";

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let result = match args.next().as_deref() {
        Some("--version") => {
            println!("{}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        Some("--stdio") => herderd::session::serve(io::stdin().lock(), io::stdout().lock()),
        Some("--socket") => match args.next() {
            Some(path) => idle_timeout(args).and_then(|grace| listen(PathBuf::from(path), grace)),
            None => usage(),
        },
        _ => usage(),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("herderd: {error}");
            ExitCode::FAILURE
        }
    }
}

fn usage<T>() -> io::Result<T> {
    Err(io::Error::new(io::ErrorKind::InvalidInput, USAGE))
}

/// How long to stay up with nothing to do. Tests shorten it.
fn idle_timeout(mut args: impl Iterator<Item = String>) -> io::Result<Duration> {
    match args.next().as_deref() {
        None => Ok(herderd::idle::DEFAULT_GRACE),
        Some("--idle-timeout") => args
            .next()
            .and_then(|seconds| seconds.parse::<f64>().ok())
            .and_then(|seconds| Duration::try_from_secs_f64(seconds).ok())
            .map_or_else(usage, Ok),
        Some(_) => usage(),
    }
}

fn listen(path: PathBuf, grace: Duration) -> io::Result<()> {
    let listener = herderd::transport::bind(&path)?;
    herderd::transport::serve_until_idle(listener, &path, grace)
}
