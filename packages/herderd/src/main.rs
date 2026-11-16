use std::io;
use std::path::PathBuf;
use std::process::ExitCode;
use std::thread;

const USAGE: &str = "usage: herderd --socket PATH | --stdio | --version";

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let result = match args.next().as_deref() {
        Some("--version") => {
            println!("{}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        Some("--stdio") => herderd::session::serve(io::stdin().lock(), io::stdout().lock()),
        Some("--socket") => match args.next() {
            Some(path) => listen(PathBuf::from(path)),
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

fn usage() -> io::Result<()> {
    Err(io::Error::new(io::ErrorKind::InvalidInput, USAGE))
}

fn listen(path: PathBuf) -> io::Result<()> {
    let listener = herderd::transport::bind(&path)?;
    for stream in listener.incoming() {
        let stream = stream?;
        match herderd::transport::peer_is_owner(&stream) {
            Ok(true) => {}
            _ => continue,
        }
        thread::spawn(move || {
            if let Ok(reader) = stream.try_clone() {
                let _ = herderd::session::serve(reader, stream);
            }
        });
    }
    Ok(())
}
