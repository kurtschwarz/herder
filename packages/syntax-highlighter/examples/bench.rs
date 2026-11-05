fn main() {
    for path in std::env::args().skip(1) {
        let source = std::fs::read_to_string(&path).unwrap();
        let id = herder_syntax::identify(&path, &source);
        let Some(language) = herder_syntax::LANGUAGES.get(id.wrapping_sub(1) as usize) else {
            println!("{path}: no language");
            continue;
        };
        // Warm the query cache, which is a one-off per language per process.
        let cold = std::time::Instant::now();
        let n = herder_syntax::highlight(language, &source).len();
        let cold = cold.elapsed();

        let mut best = std::time::Duration::MAX;
        for _ in 0..10 {
            let t = std::time::Instant::now();
            std::hint::black_box(herder_syntax::highlight(language, &source));
            best = best.min(t.elapsed());
        }
        println!(
            "{:>9} bytes  {:>6} lines  {:>6} tokens  cold {:>8.2?}  warm {:>8.2?}  {path}",
            source.len(), source.lines().count(), n, cold, best
        );
    }
}
