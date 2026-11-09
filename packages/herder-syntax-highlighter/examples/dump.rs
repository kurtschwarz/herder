//! Prints the tokens for a file, one per line.
//!
//! `cargo run --example dump -- src/lib.rs`
//!
//! For working out why something is the wrong colour: it shows the kind and the
//! exact text each token covers, which is faster than reading a grammar's
//! `highlights.scm` and guessing.

fn main() {
    let Some(path) = std::env::args().nth(1) else {
        eprintln!("usage: dump <file>");
        std::process::exit(2);
    };
    let source = match std::fs::read_to_string(&path) {
        Ok(source) => source,
        Err(error) => {
            eprintln!("{path}: {error}");
            std::process::exit(1);
        }
    };

    let id = herder_syntax::identify(&path, &source);
    let Some(language) = herder_syntax::LANGUAGES.get(id.wrapping_sub(1) as usize) else {
        eprintln!("{path}: no language claims this file");
        return;
    };
    println!("{path}: {}", language.name);

    let units: Vec<u16> = source.encode_utf16().collect();
    for token in herder_syntax::highlight(language, &source) {
        let text = String::from_utf16_lossy(&units[token.start as usize..token.end as usize]);
        println!(
            "{:>7}..{:<7} {:>2}  {text:?}",
            token.start, token.end, token.kind
        );
    }
}
