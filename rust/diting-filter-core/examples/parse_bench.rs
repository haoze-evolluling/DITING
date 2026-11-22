use std::time::Instant;

use diting_filter_core::parse::parse_document;

fn main() {
    let path = std::env::args().nth(1).expect("corpus path");
    let text = std::fs::read_to_string(&path).expect("read corpus");

    let mut best = f64::MAX;
    let mut rules = 0usize;
    for _ in 0..5 {
        let started = Instant::now();
        let parsed = parse_document(&text);
        let elapsed = started.elapsed().as_secs_f64() * 1000.0;
        rules = parsed.len();
        best = best.min(elapsed);
    }

    let megabytes = text.len() as f64 / (1024.0 * 1024.0);
    println!(
        "{} bytes, {rules} rules: {best:.1} ms ({:.1} MB/s)",
        text.len(),
        megabytes / (best / 1000.0)
    );
}
